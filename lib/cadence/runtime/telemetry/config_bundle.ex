defmodule Cadence.Runtime.Telemetry.ConfigBundle do
  @moduledoc """
  Versioned config bundle stored in persistent_term for runtime access.

  This bundle is the single source of truth for runtime configuration.
  It is produced by the control plane (MissionConfig) and consumed by
  runtime components without any database access.
  """

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.ProtocolConfig
  alias Cadence.Runtime.Telemetry.DerivedItems.Cache, as: DerivedItemsCache
  alias Cadence.Runtime.Telemetry.PacketCatalog

  @type t :: %__MODULE__{
          mission_id: String.t(),
          config_version: non_neg_integer(),
          organization_id: String.t() | nil,
          packet_defs: list(),
          packet_catalog_defs: list(),
          packet_catalog: map(),
          targets: list(),
          targets_by_identifier: map(),
          target_ids_by_identifier: map(),
          derived_item_defs: list(),
          derived_defs: list(),
          derived_packet_index: map(),
          limit_defs: map(),
          interfaces: list(),
          interface_vcids: list(),
          target_interface_routings: list(),
          transport_interfaces: list(),
          links: list(),
          bindings: list(),
          bindings_by_interface: map(),
          active_selections: list(),
          channel_targets: list(),
          channels_by_target: map(),
          protocol_defaults_by_scid: map(),
          channel_protocol_overrides: map(),
          effective_protocols_by_channel: map(),
          alarm_rules: list(),
          command_defs: map()
        }

  defstruct [
    :mission_id,
    :config_version,
    :organization_id,
    packet_defs: [],
    packet_catalog_defs: [],
    packet_catalog: %{},
    targets: [],
    targets_by_identifier: %{},
    target_ids_by_identifier: %{},
    derived_item_defs: [],
    derived_defs: [],
    derived_packet_index: %{},
    limit_defs: %{},
    interfaces: [],
    interface_vcids: [],
    target_interface_routings: [],
    transport_interfaces: [],
    links: [],
    bindings: [],
    bindings_by_interface: %{},
    active_selections: [],
    channel_targets: [],
    channels_by_target: %{},
    protocol_defaults_by_scid: %{},
    channel_protocol_overrides: %{},
    effective_protocols_by_channel: %{},
    alarm_rules: [],
    command_defs: %{}
  ]

  @spec from_config(MissionConfig.t()) :: t()
  def from_config(%MissionConfig{} = config) do
    {derived_defs, derived_packet_index} =
      case DerivedItemsCache.prepare_defs(config.derived_item_defs) do
        {:ok, {defs, packet_index}} -> {defs, packet_index}
        _ -> {[], %{}}
      end

    packet_catalog_defs = Map.get(config, :packet_catalog_defs, [])
    targets = Map.get(config, :targets, [])
    target_ids_by_identifier = build_target_id_lookup(targets)
    targets_by_identifier = build_target_lookup(targets)
    bindings = Map.get(config, :bindings, [])
    channel_targets = Map.get(config, :channel_targets, [])
    links = Map.get(config, :links, [])
    protocol_defaults_by_scid = build_protocol_defaults_by_scid(links)
    channel_protocol_overrides = build_channel_protocol_overrides(links)

    effective_protocols_by_channel =
      build_effective_protocols(protocol_defaults_by_scid, channel_protocol_overrides, links)

    %__MODULE__{
      mission_id: config.mission_id,
      config_version: config.config_generation,
      organization_id: config.organization_id,
      packet_defs: config.packet_defs,
      packet_catalog_defs: packet_catalog_defs,
      packet_catalog: build_packet_catalog(packet_catalog_defs, targets),
      targets: targets,
      targets_by_identifier: targets_by_identifier,
      target_ids_by_identifier: target_ids_by_identifier,
      derived_item_defs: config.derived_item_defs,
      derived_defs: derived_defs,
      derived_packet_index: derived_packet_index,
      limit_defs: config.limit_defs,
      interfaces: config.interfaces,
      interface_vcids: config.interface_vcids,
      target_interface_routings: config.target_interface_routings,
      transport_interfaces: config.transport_interfaces,
      links: links,
      bindings: bindings,
      bindings_by_interface: build_bindings_by_interface(bindings),
      active_selections: config.active_selections,
      channel_targets: channel_targets,
      channels_by_target: build_channels_by_target(channel_targets),
      protocol_defaults_by_scid: protocol_defaults_by_scid,
      channel_protocol_overrides: channel_protocol_overrides,
      effective_protocols_by_channel: effective_protocols_by_channel,
      alarm_rules: config.alarm_rules,
      command_defs: config.command_defs
    }
  end

  @spec store(t()) :: :ok
  def store(%__MODULE__{} = bundle) do
    :persistent_term.put(key(bundle.mission_id), bundle)
    :ok
  end

  @spec fetch(String.t()) :: {:ok, t()} | {:error, :not_found}
  def fetch(mission_id) when is_binary(mission_id) do
    case :persistent_term.get(key(mission_id), nil) do
      nil -> {:error, :not_found}
      bundle -> {:ok, bundle}
    end
  end

  defp key(mission_id), do: {:cadence, :config_bundle, mission_id}

  defp build_packet_catalog(packet_catalog_defs, targets)
       when is_list(packet_catalog_defs) and is_list(targets) do
    if packet_catalog_defs != [] do
      PacketCatalog.build_catalog(packet_catalog_defs, targets)
    else
      %{}
    end
  end

  defp build_packet_catalog(_packet_catalog_defs, _targets), do: %{}

  defp build_target_id_lookup(targets) do
    Enum.reduce(targets, %{}, fn target, acc ->
      target_id = Map.get(target, :id)

      acc
      |> maybe_put_target_key(Map.get(target, :identifier), target_id)
      |> maybe_put_target_key(Map.get(target, :name), target_id)
    end)
  end

  defp build_target_lookup(targets) do
    Enum.reduce(targets, %{}, fn target, acc ->
      target_id = Map.get(target, :id)

      acc
      |> maybe_put_target_key(Map.get(target, :identifier), target)
      |> maybe_put_target_key(Map.get(target, :name), target)
      |> maybe_put_target_key(target_id, target)
    end)
  end

  defp maybe_put_target_key(acc, key, value) when is_binary(key) do
    Map.put(acc, key, value)
  end

  defp maybe_put_target_key(acc, _key, _value), do: acc

  defp build_channels_by_target(channel_targets) do
    Enum.reduce(channel_targets, %{}, fn channel_target, acc ->
      target_id = Map.get(channel_target, :target_id)
      scid = Map.get(channel_target, :scid)
      vcid = Map.get(channel_target, :vcid)

      if is_integer(scid) and is_integer(vcid) do
        channel_id = ChannelId.new(scid, vcid, Map.get(channel_target, :map_id))
        Map.update(acc, target_id, [channel_id], fn existing -> [channel_id | existing] end)
      else
        acc
      end
    end)
    |> Map.new(fn {target_id, channels} ->
      {target_id, Enum.uniq_by(channels, &ChannelId.key/1)}
    end)
  end

  defp build_bindings_by_interface(bindings) do
    bindings
    |> Enum.filter(fn binding ->
      (binding.desired_state in [:active, :draining] and
         binding.direction in [:downlink, :both] and
         binding.channel) &&
        Map.get(binding.channel, :enabled, true) == true
    end)
    |> Enum.reduce(%{}, fn binding, acc ->
      channel = binding.channel
      scid = Map.get(channel, :scid)
      vcid = Map.get(channel, :vcid)

      if is_integer(scid) and is_integer(vcid) do
        channel_id = ChannelId.new(scid, vcid, Map.get(channel, :map_id))

        Map.update(acc, binding.interface_id, [channel_id], fn existing ->
          [channel_id | existing]
        end)
      else
        acc
      end
    end)
    |> Map.new(fn {interface_id, channels} ->
      {interface_id, Enum.uniq_by(channels, &ChannelId.key/1)}
    end)
  end

  defp build_protocol_defaults_by_scid(links) do
    Enum.reduce(links, %{}, fn link, acc ->
      defaults =
        case Map.get(link, :protocol_config) do
          nil -> %{}
          config -> Map.get(config, :config, %{})
        end

      Map.put(acc, link.scid, defaults || %{})
    end)
  end

  defp build_channel_protocol_overrides(links) do
    links
    |> List.wrap()
    |> Enum.flat_map(&channel_override_entries/1)
    |> Map.new()
  end

  defp build_effective_protocols(defaults_by_scid, overrides_by_channel, links) do
    links
    |> List.wrap()
    |> Enum.flat_map(&effective_protocol_entries(&1, defaults_by_scid, overrides_by_channel))
    |> Map.new()
  end

  defp channel_override_entries(link) do
    link
    |> Map.get(:channels, [])
    |> Enum.flat_map(&channel_override_entry/1)
  end

  defp channel_override_entry(channel) do
    channel_id = ChannelId.new(channel.scid, channel.vcid, channel.map_id)

    overrides =
      case Map.get(channel, :protocol_config) do
        nil -> nil
        config -> Map.get(config, :overrides, %{})
      end

    if is_map(overrides) and overrides != %{} do
      [{ChannelId.key(channel_id), overrides}]
    else
      []
    end
  end

  defp effective_protocol_entries(link, defaults_by_scid, overrides_by_channel) do
    defaults = Map.get(defaults_by_scid, link.scid, %{})

    link
    |> Map.get(:channels, [])
    |> Enum.flat_map(fn channel ->
      channel_id = ChannelId.new(channel.scid, channel.vcid, channel.map_id)
      overrides = Map.get(overrides_by_channel, ChannelId.key(channel_id), %{})

      if defaults == %{} and overrides == %{} do
        []
      else
        effective = ProtocolConfig.effective_config(defaults, overrides, scid: link.scid)
        [{ChannelId.key(channel_id), effective}]
      end
    end)
  end
end
