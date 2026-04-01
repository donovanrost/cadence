defmodule Cadence.Runtime.Links.ConfigReconciler do
  @moduledoc """
  Applies desired configuration to runtime processes for a mission.
  """

  use GenServer

  require Logger

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.{Binding, LinkController, ProtocolConfig, Supervisor}
  alias Cadence.Runtime.Protocol.ChannelService
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor
  alias Cadence.Runtime.Router
  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Transport
  alias Cadence.Runtime.Transport.InterfaceSupervisor

  defmodule State do
    @moduledoc false
    defstruct [:organization_id, :mission_id]
  end

  @registry Cadence.MissionRegistry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(mission_id))
  end

  @spec reconcile(String.t()) :: :ok
  def reconcile(mission_id) do
    GenServer.cast(via_tuple(mission_id), :reconcile)
  end

  @impl true
  def init(opts) do
    state = %State{
      organization_id: Keyword.fetch!(opts, :organization_id),
      mission_id: Keyword.fetch!(opts, :mission_id)
    }

    Logger.debug("Starting Links.ConfigReconciler for mission_id=#{state.mission_id}")

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{state.mission_id}:config")
    send(self(), :reconcile)
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "Stopping Links.ConfigReconciler for mission_id=#{state.mission_id} reason=#{inspect(reason)}"
    )

    :ok
  end

  @impl true
  def handle_info(:reconcile, state) do
    {:noreply, do_reconcile(state)}
  end

  @impl true
  def handle_info({:config_updated, _version}, state) do
    {:noreply, do_reconcile(state)}
  end

  @impl true
  def handle_cast(:reconcile, state) do
    {:noreply, do_reconcile(state)}
  end

  defp do_reconcile(state) do
    case ConfigBundle.fetch(state.mission_id) do
      {:ok, bundle} ->
        Logger.debug(
          "Applying link config for mission_id=#{state.mission_id} generation=#{bundle.config_version}"
        )

        apply_transports(state, bundle)
        apply_links(state, bundle)
        apply_bindings(state, bundle)
        apply_selections(state, bundle)
        apply_channel_protocols(state, bundle)
        sync_connected_transports(state, bundle)

        state

      {:error, _} ->
        Logger.debug(
          "Config bundle missing for mission_id=#{state.mission_id}; skipping reconcile"
        )

        state
    end
  end

  defp apply_transports(state, bundle) do
    bundle
    |> Map.get(:transport_interfaces, [])
    |> Enum.each(&apply_transport(state, &1))
  end

  defp apply_transport(state, transport) do
    if transport.enabled do
      _ = InterfaceSupervisor.ensure_started(state.mission_id, transport.id, transport)
    else
      _ = InterfaceSupervisor.ensure_stopped(state.mission_id, transport.id)
    end
  end

  defp apply_links(state, bundle) do
    bundle
    |> Map.get(:links, [])
    |> Enum.each(fn link ->
      :ok = Supervisor.ensure_link(state.mission_id, link.scid)
      :ok = apply_link_config_snapshot(state, bundle, link)
    end)
  end

  defp apply_channel_protocols(state, bundle) do
    Enum.each(bundle.effective_protocols_by_channel, fn {key, protocol_config} ->
      with %ChannelId{} = channel_id <- channel_id_from_key(key),
           {:ok, _pid} <- ProtocolSupervisor.lookup_channel(state.mission_id, channel_id) do
        snapshot = %{
          config_version: bundle.config_version,
          protocol_config: protocol_config
        }

        ChannelService.apply_config(state.mission_id, channel_id, snapshot)
      end
    end)
  end

  defp apply_bindings(state, bundle) do
    bundle
    |> Map.get(:bindings, [])
    |> Enum.group_by(& &1.channel_id)
    |> Enum.each(fn {_channel_id, channel_bindings} ->
      apply_bindings_for_channel(state, channel_bindings)
    end)
  end

  defp apply_bindings_for_channel(_state, []), do: :ok

  defp apply_bindings_for_channel(state, channel_bindings) do
    runtime_bindings = Enum.map(channel_bindings, &to_runtime_binding/1)
    LinkController.apply_desired_bindings(state.mission_id, runtime_bindings)
  end

  defp apply_selections(state, bundle) do
    bundle
    |> Map.get(:active_selections, [])
    |> Enum.each(&apply_selection(state, &1))
  end

  defp apply_selection(state, selection) do
    channel = selection.channel
    channel_id = ChannelId.new(channel.scid, channel.vcid, channel.map_id)

    selection_value =
      case selection.binding do
        nil -> nil
        binding -> binding.transport_id
      end

    LinkController.set_active_selection(
      state.mission_id,
      channel_id,
      selection.direction,
      selection_value
    )
  end

  defp sync_connected_transports(state, bundle) do
    bundle
    |> Map.get(:transport_interfaces, [])
    |> Enum.each(fn transport ->
      if Transport.connected?(state.mission_id, transport.id) do
        Router.transport_connected(state.mission_id, transport.id)
      end
    end)
  end

  defp apply_link_config_snapshot(state, bundle, link) do
    defaults_raw = Map.get(bundle.protocol_defaults_by_scid, link.scid, %{})

    default_effective =
      if defaults_raw == %{} do
        %{}
      else
        ProtocolConfig.effective_config(defaults_raw, %{}, scid: link.scid)
      end

    channel_overrides =
      bundle.channel_protocol_overrides
      |> Enum.filter(fn {{scid, _vcid, _map_id}, _overrides} -> scid == link.scid end)
      |> Map.new()

    effective_protocols =
      bundle.effective_protocols_by_channel
      |> Enum.filter(fn {{scid, _vcid, _map_id}, _config} -> scid == link.scid end)
      |> Map.new()

    snapshot = %{
      config_version: bundle.config_version,
      link_defaults: default_effective,
      channel_overrides: channel_overrides,
      effective_protocols: effective_protocols
    }

    LinkController.apply_config(state.mission_id, link.scid, snapshot)
  end

  defp channel_id_from_key({scid, vcid, map_id})
       when is_integer(scid) and is_integer(vcid) do
    ChannelId.new(scid, vcid, map_id)
  end

  defp channel_id_from_key(_), do: nil

  defp to_runtime_binding(binding) do
    channel = binding.channel
    channel_id = ChannelId.new(channel.scid, channel.vcid, channel.map_id)

    %Binding{
      mission_id: binding.mission_id,
      channel_id: channel_id,
      transport_id: binding.transport_id,
      direction: binding.direction,
      role: binding.role,
      priority: binding.priority,
      desired_state: binding.desired_state,
      observed_state: :inactive
    }
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:link_config_reconciler, mission_id}}}
  end
end
