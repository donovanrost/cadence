defmodule Cadence.Runtime.Missions.RuntimeBootstrapper do
  @moduledoc """
  Boots link and channel bindings for a mission from MissionConfig.
  """

  use GenServer

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Domain.Interfaces.Entities.TargetInterface, as: TargetInterfaceEntity
  alias Cadence.Interfaces.InterfaceVcid
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.Binding
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Links.ProtocolConfig
  alias Cadence.Runtime.Links.Supervisor, as: LinksSupervisor
  alias Cadence.Runtime.Links.TargetDirectory
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor

  @doc false
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.mission_id))
  end

  @impl true
  def init(%MissionConfig{} = config) do
    send(self(), :bootstrap)
    {:ok, %{config: config}}
  end

  @impl true
  def handle_info(:bootstrap, %{config: %MissionConfig{} = config} = state) do
    bindings = build_bindings(config)
    protocol_configs = build_link_protocol_configs(config)

    Enum.each(bindings, fn %Binding{} = binding ->
      protocol_config = Map.get(protocol_configs, binding.channel_id.scid, %{})
      LinksSupervisor.ensure_link(binding.mission_id, binding.channel_id.scid, protocol_config)
      _ = ProtocolSupervisor.ensure_channel(binding.mission_id, binding.channel_id)
      LinkController.set_binding(binding)
    end)

    register_target_channels(config, bindings)

    {:noreply, state}
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:runtime_bootstrapper, mission_id}}}
  end

  defp build_bindings(%MissionConfig{} = config) do
    config.target_interface_routings
    |> Enum.flat_map(fn %TargetInterfaceEntity{} = routing ->
      build_bindings_for_routing(config, routing)
    end)
  end

  defp build_bindings_for_routing(%MissionConfig{} = config, %TargetInterfaceEntity{} = routing) do
    case routing.scid do
      nil ->
        []

      scid ->
        vcids = vcids_for_routing(config.interface_vcids, routing)
        direction = binding_direction(routing)

        Enum.map(vcids, fn vcid ->
          %Binding{
            mission_id: config.mission_id,
            channel_id: ChannelId.new(scid, vcid),
            interface_id: routing.interface_id,
            direction: direction,
            role: :primary,
            priority: 0,
            desired_state: :active,
            observed_state: :inactive
          }
        end)
    end
  end

  defp vcids_for_routing(interface_vcids, %TargetInterfaceEntity{} = routing) do
    matches =
      interface_vcids
      |> Enum.filter(fn %InterfaceVcid{} = mapping ->
        mapping.interface_id == routing.interface_id and
          (is_nil(mapping.target_id) or mapping.target_id == routing.target_id)
      end)

    case matches do
      [] ->
        [0]

      mappings ->
        mappings
        |> Enum.map(& &1.vcid)
        |> Enum.uniq()
    end
  end

  defp binding_direction(%TargetInterfaceEntity{direction: :read}), do: :downlink
  defp binding_direction(%TargetInterfaceEntity{direction: :write}), do: :uplink
  defp binding_direction(%TargetInterfaceEntity{direction: :read_write}), do: :both

  defp register_target_channels(%MissionConfig{} = config, bindings) do
    Enum.each(bindings, fn binding ->
      register_target_channel(config, binding)
    end)
  end

  defp register_target_channel(%MissionConfig{} = config, %Binding{} = binding) do
    config.target_interface_routings
    |> Enum.filter(fn routing ->
      routing.interface_id == binding.interface_id and
        routing.scid == binding.channel_id.scid
    end)
    |> Enum.map(& &1.target_id)
    |> Enum.uniq()
    |> Enum.each(fn target_id ->
      TargetDirectory.register(config.mission_id, target_id, binding.channel_id)
    end)
  end

  defp build_link_protocol_configs(%MissionConfig{} = config) do
    interface_by_id =
      config.interfaces
      |> Enum.map(fn interface -> {interface.id, interface} end)
      |> Map.new()

    config.target_interface_routings
    |> Enum.filter(& &1.scid)
    |> Enum.reduce(%{}, fn routing, acc ->
      add_protocol_config(acc, routing, interface_by_id)
    end)
  end

  defp add_protocol_config(acc, routing, interface_by_id) do
    interface = Map.get(interface_by_id, routing.interface_id)
    protocol_config = if interface, do: ProtocolConfig.from_interface(interface), else: nil
    put_link_protocol_config(acc, routing.scid, protocol_config)
  end

  defp put_link_protocol_config(acc, scid, protocol_config) do
    acc
    |> Map.update(scid, %{protocols_by_interface: %{}}, fn config ->
      config
      |> put_protocol(protocol_config)
    end)
  end

  defp put_protocol(config, nil), do: config

  defp put_protocol(config, protocol_config) do
    put_in(config, [:protocols_by_interface, protocol_config.interface_id], protocol_config)
  end
end
