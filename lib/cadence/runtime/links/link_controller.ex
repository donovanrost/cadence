defmodule Cadence.Runtime.Links.LinkController do
  @moduledoc """
  Link controller for a spacecraft, keyed by {mission_id, scid}.

  Owns protocol configuration, bindings, and link policy. Interfaces are
  ephemeral; bindings define desired and observed state independently of
  interface connectivity.
  """

  use GenServer

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.Binding
  alias Cadence.Runtime.Protocol.ChannelService
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :scid,
      bindings: %{},
      interface_states: %{},
      protocol_config: %{}
    ]
  end

  @registry Cadence.MissionRegistry

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    scid = Keyword.fetch!(opts, :scid)
    protocol_config = Keyword.get(opts, :protocol_config, %{})

    GenServer.start_link(__MODULE__, {mission_id, scid, protocol_config},
      name: via_tuple(mission_id, scid)
    )
  end

  @spec via_tuple(String.t(), non_neg_integer()) :: {:via, Registry, {atom(), term()}}
  def via_tuple(mission_id, scid) do
    {:via, Registry, {@registry, {:link_controller, mission_id, scid}}}
  end

  @spec set_binding(Binding.t()) :: :ok
  def set_binding(%Binding{} = binding) do
    GenServer.call(
      via_tuple(binding.mission_id, binding.channel_id.scid),
      {:set_binding, binding}
    )
  end

  @spec set_binding_state(String.t(), ChannelId.t(), String.t(), Binding.state()) :: :ok
  def set_binding_state(mission_id, %ChannelId{} = channel_id, interface_id, desired_state) do
    GenServer.call(
      via_tuple(mission_id, channel_id.scid),
      {:set_binding_state, channel_id, interface_id, desired_state}
    )
  end

  @spec list_bindings(String.t(), non_neg_integer()) :: [Binding.t()]
  def list_bindings(mission_id, scid) do
    GenServer.call(via_tuple(mission_id, scid), :list_bindings)
  end

  @spec interface_state(String.t(), non_neg_integer(), String.t(), :up | :down) :: :ok
  def interface_state(mission_id, scid, interface_id, state) do
    GenServer.cast(via_tuple(mission_id, scid), {:interface_state, interface_id, state})
  end

  @spec classify_downlink(String.t(), non_neg_integer(), String.t(), binary(), map()) ::
          {:ok, ChannelId.t()} | :ignore
  def classify_downlink(mission_id, scid, interface_id, bytes, meta) do
    GenServer.call(via_tuple(mission_id, scid), {:classify, interface_id, bytes, meta})
  end

  @spec route_downlink(String.t(), non_neg_integer(), String.t(), binary(), map()) :: :ok
  def route_downlink(mission_id, scid, interface_id, bytes, meta) do
    GenServer.cast(via_tuple(mission_id, scid), {:route_downlink, interface_id, bytes, meta})
  end

  @spec active_uplink_interface(String.t(), ChannelId.t()) :: String.t() | nil
  def active_uplink_interface(mission_id, %ChannelId{} = channel_id) do
    GenServer.call(via_tuple(mission_id, channel_id.scid), {:active_uplink, channel_id})
  end

  @spec binding_active?(String.t(), ChannelId.t(), String.t(), :uplink | :downlink) :: boolean()
  def binding_active?(mission_id, %ChannelId{} = channel_id, interface_id, direction)
      when is_binary(interface_id) do
    GenServer.call(
      via_tuple(mission_id, channel_id.scid),
      {:binding_active, channel_id, interface_id, direction}
    )
  end

  @spec protocol_config_for_interface(String.t(), non_neg_integer(), String.t()) ::
          {:ok, map()} | :error
  def protocol_config_for_interface(mission_id, scid, interface_id) do
    GenServer.call(via_tuple(mission_id, scid), {:protocol_config, interface_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init({mission_id, scid, protocol_config}) do
    {:ok,
     %State{
       mission_id: mission_id,
       scid: scid,
       protocol_config: protocol_config
     }}
  end

  @impl true
  def handle_call(:list_bindings, _from, state) do
    {:reply, Map.values(state.bindings), state}
  end

  def handle_call({:set_binding, %Binding{} = binding}, _from, state) do
    updated = put_binding(state, binding)
    {:reply, :ok, updated}
  end

  def handle_call({:set_binding_state, channel_id, interface_id, desired_state}, _from, state) do
    updated = update_binding_state(state, channel_id, interface_id, desired_state)
    {:reply, :ok, updated}
  end

  def handle_call({:classify, interface_id, _bytes, meta}, _from, state) do
    {:reply, classify_channel(state, interface_id, meta), state}
  end

  def handle_call({:active_uplink, %ChannelId{} = channel_id}, _from, state) do
    {:reply, pick_active_uplink(state, channel_id), state}
  end

  def handle_call({:binding_active, channel_id, interface_id, direction}, _from, state) do
    {:reply, binding_active_in_state?(state, channel_id, interface_id, direction), state}
  end

  def handle_call({:protocol_config, interface_id}, _from, state) do
    {:reply, fetch_protocol_config(state, interface_id), state}
  end

  @impl true
  def handle_cast({:interface_state, interface_id, state_value}, state) do
    updated = %{
      state
      | interface_states: Map.put(state.interface_states, interface_id, state_value)
    }

    {:noreply, refresh_observed_bindings(updated, interface_id)}
  end

  def handle_cast({:route_downlink, interface_id, bytes, meta}, state) do
    case classify_channel(state, interface_id, meta) do
      {:ok, channel_id} ->
        route_to_channel(state, channel_id, interface_id, bytes, meta)

      :ignore ->
        :ok
    end

    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internal Helpers
  # ---------------------------------------------------------------------------

  defp put_binding(state, %Binding{} = binding) do
    _ = register_binding(binding)
    %{state | bindings: Map.put(state.bindings, Binding.key(binding), binding)}
  end

  defp update_binding_state(state, %ChannelId{} = channel_id, interface_id, desired_state) do
    updated =
      state.bindings
      |> Enum.map(fn {binding_key, binding} ->
        if match_binding?(binding_key, channel_id, interface_id) do
          {binding_key, %{binding | desired_state: desired_state}}
        else
          {binding_key, binding}
        end
      end)
      |> Map.new()

    %{state | bindings: updated}
  end

  defp match_binding?({channel_id, interface_id, _direction}, channel_id, interface_id), do: true
  defp match_binding?(_, _, _), do: false

  defp classify_channel(state, interface_id, meta) do
    case meta do
      %{channel_id: %ChannelId{} = channel_id} ->
        {:ok, channel_id}

      %{scid: scid, vcid: vcid} when is_integer(scid) and is_integer(vcid) ->
        {:ok, ChannelId.new(scid, vcid)}

      _ ->
        bindings = bindings_for_interface(state, interface_id, :downlink)

        case Enum.map(bindings, & &1.channel_id) |> Enum.uniq() do
          [channel_id] -> {:ok, channel_id}
          _ -> :ignore
        end
    end
  end

  defp bindings_for_interface(state, interface_id, direction) do
    state.bindings
    |> Map.values()
    |> Enum.filter(fn binding ->
      binding.interface_id == interface_id and Binding.allows_direction?(binding, direction)
    end)
  end

  defp route_to_channel(state, channel_id, interface_id, bytes, meta) do
    active? = binding_active_in_state?(state, channel_id, interface_id, :downlink)

    if active? do
      ensure_channel(state.mission_id, channel_id)
      ChannelService.handle_downlink(state.mission_id, channel_id, bytes, meta)
    end
  end

  defp binding_active_in_state?(state, channel_id, interface_id, direction) do
    state.bindings
    |> Map.values()
    |> Enum.any?(fn binding ->
      binding.interface_id == interface_id and
        binding.channel_id == channel_id and
        Binding.allows_direction?(binding, direction) and
        binding.desired_state == :active and
        binding.observed_state == :active
    end)
  end

  defp pick_active_uplink(state, %ChannelId{} = channel_id) do
    state.bindings
    |> Map.values()
    |> Enum.filter(fn binding ->
      binding.channel_id == channel_id and
        Binding.allows_direction?(binding, :uplink) and
        binding.desired_state == :active and
        binding.observed_state == :active
    end)
    |> Enum.sort_by(& &1.priority)
    |> case do
      [] -> nil
      [binding | _] -> binding.interface_id
    end
  end

  defp refresh_observed_bindings(state, interface_id) do
    observed_state = observed_state_for(state, interface_id)

    updated =
      state.bindings
      |> Enum.map(fn {binding_key, binding} ->
        {binding_key, maybe_update_binding(binding, interface_id, observed_state)}
      end)
      |> Map.new()

    %{state | bindings: updated}
  end

  defp observed_state_for(state, interface_id) do
    if Map.get(state.interface_states, interface_id, :down) == :up, do: :active, else: :inactive
  end

  defp maybe_update_binding(binding, interface_id, observed_state) do
    if binding.interface_id == interface_id,
      do: %{binding | observed_state: observed_state},
      else: binding
  end

  defp ensure_channel(mission_id, %ChannelId{} = channel_id) do
    ProtocolSupervisor.ensure_channel(mission_id, channel_id)
  end

  defp fetch_protocol_config(state, interface_id) do
    case get_in(state.protocol_config, [:protocols_by_interface, interface_id]) do
      nil -> :error
      protocol_config -> {:ok, protocol_config}
    end
  end

  defp register_binding(%Binding{} = binding) do
    key = {:link_binding, binding.mission_id, binding.channel_id.scid, binding.interface_id}

    case Registry.register(@registry, key, :binding) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end
end
