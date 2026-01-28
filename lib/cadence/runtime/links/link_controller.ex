defmodule Cadence.Runtime.Links.LinkController do
  @moduledoc """
  Link controller for a spacecraft, keyed by {mission_id, scid}.

  Owns protocol configuration, bindings, and link policy. Interfaces are
  ephemeral; bindings define desired and observed state independently of
  interface connectivity.
  """

  use GenServer

  require Logger

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.Binding
  alias Cadence.Runtime.Protocol.ChannelService
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :scid,
      config_version: nil,
      link_defaults: %{},
      channel_overrides: %{},
      effective_protocols: %{},
      bindings: %{},
      interface_states: %{},
      selections: %{}
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
    config_snapshot = Keyword.get(opts, :config_snapshot, %{})

    GenServer.start_link(__MODULE__, {mission_id, scid, config_snapshot},
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

  @spec apply_desired_bindings(String.t(), [Binding.t()]) :: :ok
  def apply_desired_bindings(_mission_id, []), do: :ok

  def apply_desired_bindings(mission_id, [%Binding{} = binding | _] = bindings) do
    GenServer.call(
      via_tuple(mission_id, binding.channel_id.scid),
      {:apply_desired_bindings, bindings}
    )
  end

  @spec set_binding_state(String.t(), ChannelId.t(), String.t(), Binding.state()) :: :ok
  def set_binding_state(mission_id, %ChannelId{} = channel_id, interface_id, desired_state) do
    GenServer.call(
      via_tuple(mission_id, channel_id.scid),
      {:set_binding_state, channel_id, interface_id, desired_state}
    )
  end

  @spec set_active_selection(
          String.t(),
          ChannelId.t(),
          :uplink | :downlink,
          String.t() | :auto | nil
        ) ::
          :ok
  def set_active_selection(mission_id, %ChannelId{} = channel_id, direction, selection) do
    GenServer.call(
      via_tuple(mission_id, channel_id.scid),
      {:set_active_selection, channel_id, direction, selection}
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

  @spec effective_protocol_config(String.t(), ChannelId.t()) ::
          {:ok, map()} | :error
  def effective_protocol_config(mission_id, %ChannelId{} = channel_id) do
    GenServer.call(via_tuple(mission_id, channel_id.scid), {:effective_protocol, channel_id})
  end

  @spec apply_config(String.t(), non_neg_integer(), map()) :: :ok
  def apply_config(mission_id, scid, snapshot) when is_map(snapshot) do
    GenServer.cast(via_tuple(mission_id, scid), {:apply_config, snapshot})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init({mission_id, scid, config_snapshot}) do
    Logger.debug("Starting LinkController for mission_id=#{mission_id} scid=#{scid}")

    {:ok, apply_config_snapshot(%State{mission_id: mission_id, scid: scid}, config_snapshot)}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping LinkController for mission_id=#{state.mission_id} scid=#{state.scid} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_call(:list_bindings, _from, state) do
    {:reply, Map.values(state.bindings), state}
  end

  def handle_call({:set_binding, %Binding{} = binding}, _from, state) do
    updated = put_binding(state, binding)
    {:reply, :ok, updated}
  end

  def handle_call({:apply_desired_bindings, bindings}, _from, state) do
    updated = replace_channel_bindings(state, bindings)
    {:reply, :ok, updated}
  end

  def handle_call({:set_binding_state, channel_id, interface_id, desired_state}, _from, state) do
    updated = update_binding_state(state, channel_id, interface_id, desired_state)
    {:reply, :ok, updated}
  end

  def handle_call({:set_active_selection, channel_id, direction, selection}, _from, state) do
    updated = put_selection(state, channel_id, direction, selection)
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

  def handle_call({:effective_protocol, %ChannelId{} = channel_id}, _from, state) do
    {:reply, fetch_effective_protocol(state, channel_id), state}
  end

  @impl true
  def handle_cast({:interface_state, interface_id, state_value}, state) do
    updated = %{
      state
      | interface_states: Map.put(state.interface_states, interface_id, state_value)
    }

    {:noreply, refresh_observed_bindings(updated, interface_id)}
  end

  def handle_cast({:apply_config, snapshot}, state) do
    {:noreply, apply_config_snapshot(state, snapshot)}
  end

  def handle_cast({:route_downlink, interface_id, bytes, meta}, state) do
    case classify_channel(state, interface_id, meta) do
      {:ok, channel_id} ->
        route_to_channel(state, channel_id, interface_id, bytes, meta)

      :ignore ->
        Logger.debug("link.route_downlink.ignore",
          mission_id: state.mission_id,
          scid: state.scid,
          interface_id: interface_id
        )

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

  defp replace_channel_bindings(state, bindings) do
    case bindings do
      [%Binding{channel_id: channel_id} | _] ->
        Enum.each(bindings, &register_binding/1)

        updated =
          state.bindings
          |> Enum.reject(fn {binding_key, _binding} ->
            channel_match?(binding_key, channel_id)
          end)
          |> Map.new()
          |> Map.merge(
            Map.new(Enum.map(bindings, fn binding -> {Binding.key(binding), binding} end))
          )

        %{state | bindings: updated}

      [] ->
        state
    end
  end

  defp channel_match?({channel_id, _interface_id, _direction}, channel_id), do: true
  defp channel_match?(_, _), do: false

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

  defp put_selection(state, %ChannelId{} = channel_id, direction, selection) do
    key = {channel_id, direction}
    %{state | selections: Map.put(state.selections, key, selection)}
  end

  defp classify_channel(state, interface_id, meta) do
    case meta do
      %{channel_id: %ChannelId{} = channel_id} ->
        # Logger.debug("[DEBUG] link.classify.meta_channel_id",
        #   mission_id: state.mission_id,
        #   scid: state.scid,
        #   interface_id: interface_id,
        #   channel_id: ChannelId.key(channel_id)
        # )

        {:ok, channel_id}

      %{scid: scid, vcid: vcid} when is_integer(scid) and is_integer(vcid) ->
        # Logger.debug("[DEBUG] link.classify.meta_scid_vcid",
        #   mission_id: state.mission_id,
        #   scid: scid,
        #   interface_id: interface_id,
        #   vcid: vcid
        # )

        {:ok, ChannelId.new(scid, vcid)}

      _ ->
        bindings = bindings_for_interface(state, interface_id, :downlink)

        case Enum.map(bindings, & &1.channel_id) |> Enum.uniq() do
          [channel_id] ->
            # Logger.debug("[DEBUG] link.classify.binding_unambiguous",
            #   mission_id: state.mission_id,
            #   scid: state.scid,
            #   interface_id: interface_id,
            #   channel_id: ChannelId.key(channel_id)
            # )

            {:ok, channel_id}

          _ ->
            # Logger.debug("[DEBUG] link.classify.ambiguous",
            #   mission_id: state.mission_id,
            #   scid: state.scid,
            #   interface_id: interface_id
            # )

            :ignore
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
      # Logger.debug("[DEBUG] link.route_downlink.active",
      #   mission_id: state.mission_id,
      #   scid: state.scid,
      #   interface_id: interface_id,
      #   channel_id: ChannelId.key(channel_id),
      #   bytes: byte_size(bytes)
      # )

      ensure_channel(state.mission_id, channel_id)
      ChannelService.handle_downlink(state.mission_id, channel_id, bytes, meta)
    else
      Logger.debug("link.route_downlink.inactive",
        mission_id: state.mission_id,
        scid: state.scid,
        interface_id: interface_id,
        channel_id: ChannelId.key(channel_id)
      )
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
    selection = Map.get(state.selections, {channel_id, :uplink})

    case selection do
      interface_id when is_binary(interface_id) ->
        if binding_active_in_state?(state, channel_id, interface_id, :uplink) do
          interface_id
        else
          nil
        end

      _ ->
        state.bindings
        |> Map.values()
        |> Enum.filter(fn binding ->
          binding.channel_id == channel_id and
            Binding.allows_direction?(binding, :uplink) and
            binding.desired_state == :active and
            binding.observed_state == :active
        end)
        |> Enum.sort_by(fn binding -> {role_rank(binding.role), binding.priority} end)
        |> case do
          [] -> nil
          [binding | _] -> binding.interface_id
        end
    end
  end

  defp role_rank(:primary), do: 0
  defp role_rank(:any), do: 1
  defp role_rank(:backup), do: 2
  defp role_rank(:replay), do: 3
  defp role_rank(_), do: 4

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

  defp fetch_effective_protocol(state, %ChannelId{} = channel_id) do
    key = ChannelId.key(channel_id)

    case Map.get(state.effective_protocols, key) do
      nil ->
        if state.link_defaults == %{} do
          :error
        else
          {:ok, state.link_defaults}
        end

      protocol_config ->
        {:ok, protocol_config}
    end
  end

  defp apply_config_snapshot(state, snapshot) do
    %State{
      state
      | config_version: Map.get(snapshot, :config_version, state.config_version),
        link_defaults: Map.get(snapshot, :link_defaults, state.link_defaults) || %{},
        channel_overrides: Map.get(snapshot, :channel_overrides, state.channel_overrides) || %{},
        effective_protocols:
          Map.get(snapshot, :effective_protocols, state.effective_protocols) || %{}
    }
  end

  defp register_binding(%Binding{} = binding) do
    key = {:link_binding, binding.mission_id, binding.channel_id.scid, binding.interface_id}

    case Registry.register(@registry, key, :binding) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end
end
