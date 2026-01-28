defmodule Cadence.Application.Missions.MissionConfig do
  @moduledoc """
  Complete configuration snapshot for a mission.

  Loaded by OrgReconciler from the database, then injected into
  MissionInstance and its children. Each component receives its
  relevant slice and holds it in GenServer state.

  ## Design Principle: Config in Process State

  Instead of ETS tables for config lookup, each component holds its config
  slice in GenServer state. This eliminates ETS copy-on-read overhead and
  simplifies the runtime model.

  ## Usage

      {:ok, config} = MissionConfig.load(mission_id)
      {:ok, _pid} = MissionSupervisor.start_mission(config)
  """

  alias Cadence.Application.Commanding.QueueSnapshotLoader
  alias Cadence.Application.Interfaces.InterfaceQueries
  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Application.Targeting.TargetQueries
  alias Cadence.Domain.Interfaces.Entities.TargetInterface, as: TargetInterfaceEntity
  alias Cadence.Interfaces.InterfaceSchema
  alias Cadence.Interfaces.InterfaceVcid
  alias Cadence.Interfaces.TargetInterface, as: TargetInterfaceSchema
  alias Cadence.Links
  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Repo
  alias Cadence.Telemetry.Database.DerivedItem
  alias Cadence.Telemetry.Packet.PacketDefinition
  alias Cadence.Transports

  import Ecto.Query

  require Logger

  @type t :: %__MODULE__{
          mission_id: String.t(),
          organization_id: String.t(),
          config_generation: integer(),
          mission: map(),
          interfaces: list(),
          targets: list(),
          target_interface_routings: list(),
          interface_vcids: list(),
          queue_snapshots: map(),
          packet_defs: list(),
          packet_catalog_defs: list(),
          command_defs: map(),
          limit_defs: map(),
          derived_item_defs: list(),
          alarm_rules: list(),
          automations: list(),
          transport_interfaces: list(),
          links: list(),
          bindings: list(),
          active_selections: list(),
          channel_targets: list()
        }

  defstruct [
    :mission_id,
    :organization_id,
    :config_generation,
    :mission,
    interfaces: [],
    targets: [],
    target_interface_routings: [],
    interface_vcids: [],
    queue_snapshots: %{},
    packet_defs: [],
    packet_catalog_defs: [],
    command_defs: %{},
    limit_defs: %{},
    derived_item_defs: [],
    alarm_rules: [],
    automations: [],
    transport_interfaces: [],
    links: [],
    bindings: [],
    active_selections: [],
    channel_targets: []
  ]

  @doc """
  Loads complete mission configuration from the database.

  This is the single function that loads ALL config needed to run a mission.
  Returns `{:ok, %MissionConfig{}}` or `{:error, reason}`.
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(mission_id) when is_binary(mission_id) do
    with {:ok, mission} <- load_mission(mission_id),
         {:ok, interfaces} <- load_interfaces(mission_id),
         {:ok, targets} <- load_targets(mission_id),
         {:ok, target_interface_routings} <- load_target_interface_routings(mission_id),
         {:ok, interface_vcids} <- load_interface_vcids(mission_id),
         :ok <- validate_tc_stream_ids(target_interface_routings, interfaces, interface_vcids),
         {:ok, queue_snapshots} <- load_queue_snapshots(mission_id, targets),
         {:ok, packet_catalog_defs} <- load_packet_catalog_defs(mission_id, targets),
         {:ok, packet_defs} <- load_packet_definitions(mission_id),
         {:ok, command_defs} <- load_command_definitions(mission_id, targets),
         {:ok, limit_defs} <- load_limit_definitions(mission_id),
         {:ok, derived_item_defs} <- load_derived_items(mission_id),
         {:ok, alarm_rules} <- load_alarm_rules(mission.organization_id, mission_id),
         {:ok, automations} <- load_automations(mission_id),
         {:ok, transport_interfaces} <-
           load_transport_interfaces(mission.organization_id, mission_id),
         {:ok, links} <- load_links(mission.organization_id, mission_id),
         {:ok, bindings} <- load_bindings(mission.organization_id, mission_id),
         {:ok, active_selections} <- load_active_selections(mission.organization_id, mission_id),
         {:ok, channel_targets} <- load_channel_targets(mission.organization_id, mission_id) do
      {:ok,
       %__MODULE__{
         mission_id: mission_id,
         organization_id: mission.organization_id,
         config_generation: mission.config_generation,
         mission: mission,
         interfaces: interfaces,
         targets: targets,
         target_interface_routings: target_interface_routings,
         interface_vcids: interface_vcids,
         queue_snapshots: queue_snapshots,
         packet_defs: packet_defs,
         packet_catalog_defs: packet_catalog_defs,
         command_defs: command_defs,
         limit_defs: limit_defs,
         derived_item_defs: derived_item_defs,
         alarm_rules: alarm_rules,
         automations: automations,
         transport_interfaces: transport_interfaces,
         links: links,
         bindings: bindings,
         active_selections: active_selections,
         channel_targets: channel_targets
       }}
    end
  end

  # ===========================================================================
  # Private Loaders
  # ===========================================================================

  defp load_mission(mission_id) do
    MissionQueries.find(mission_id)
  end

  defp load_interfaces(mission_id) do
    interfaces = InterfaceQueries.list_for_mission(mission_id)
    {:ok, interfaces}
  rescue
    e ->
      Logger.warning("Failed to load interfaces for mission #{mission_id}: #{inspect(e)}")
      {:ok, []}
  end

  defp load_targets(mission_id) do
    # TargetQueries.list/1 expects mission_id as first arg
    targets = TargetQueries.list(mission_id)
    {:ok, targets}
  rescue
    e ->
      Logger.warning("Failed to load targets for mission #{mission_id}: #{inspect(e)}")
      {:ok, []}
  end

  defp load_packet_definitions(mission_id) do
    # Load packet definitions for this mission, including items for limits config.
    packet_defs =
      from(pd in PacketDefinition,
        where: pd.mission_id == ^mission_id,
        preload: [:packet_items]
      )
      |> Repo.all()

    {:ok, packet_defs}
  end

  defp load_packet_catalog_defs(_mission_id, []), do: {:ok, []}

  defp load_packet_catalog_defs(_mission_id, targets) do
    definition_set_ids =
      targets
      |> Enum.map(&Map.get(&1, :definition_set_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if definition_set_ids == [] do
      {:ok, []}
    else
      containers =
        Cadence.MissionDatabase.Container
        |> where([c], c.definition_set_id in ^definition_set_ids)
        |> where([c], c.abstract == false or is_nil(c.abstract))
        |> preload(container_entries: [parameter: [data_type: [:default_calibrator, :unit]]])
        |> Repo.all()

      {:ok, containers}
    end
  end

  defp load_target_interface_routings(mission_id) do
    routings =
      from(ti in TargetInterfaceSchema,
        join: t in Cadence.Targets.Target,
        on: ti.target_id == t.id,
        where: t.mission_id == ^mission_id
      )
      |> Repo.all()
      |> Enum.map(&TargetInterfaceEntity.from_persistence/1)

    {:ok, routings}
  rescue
    e ->
      Logger.warning(
        "Failed to load target-interface routings for mission #{mission_id}: #{inspect(e)}"
      )

      {:ok, []}
  end

  defp load_interface_vcids(mission_id) do
    vcids =
      from(v in InterfaceVcid,
        join: i in InterfaceSchema,
        on: v.interface_id == i.id,
        where: i.mission_id == ^mission_id
      )
      |> Repo.all()

    {:ok, vcids}
  rescue
    e ->
      Logger.warning("Failed to load interface vcids for mission #{mission_id}: #{inspect(e)}")
      {:ok, []}
  end

  defp load_queue_snapshots(mission_id, targets) do
    QueueSnapshotLoader.load_for_mission(mission_id, targets)
  rescue
    e ->
      Logger.warning("Failed to load queue snapshots for mission #{mission_id}: #{inspect(e)}")
      {:ok, %{}}
  end

  defp load_command_definitions(_mission_id, targets) do
    definition_set_ids =
      targets
      |> Enum.map(&Map.get(&1, :definition_set_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if definition_set_ids == [] do
      {:ok, %{}}
    else
      commands =
        MetaCommand
        |> where([mc], mc.definition_set_id in ^definition_set_ids)
        |> where([mc], mc.abstract == false or is_nil(mc.abstract))
        |> preload([:arguments, :verifiers, :transmission_constraints, :command_container])
        |> Repo.all()

      by_definition_set =
        Enum.group_by(commands, fn command -> command.definition_set_id end)

      {:ok, by_definition_set}
    end
  end

  defp load_limit_definitions(_mission_id) do
    # Limits are derived from packet definitions and target active_limit_set.
    # Cache warming uses MissionConfig.packet_defs + targets, so keep this empty.
    {:ok, %{}}
  end

  defp load_derived_items(mission_id) do
    derived_items = DerivedItem.list_enabled(mission_id)
    derived_defs = Enum.map(derived_items, &DerivedItem.to_compute_format/1)
    {:ok, derived_defs}
  end

  defp load_alarm_rules(organization_id, mission_id) do
    {:ok, Cadence.Alarms.list_rules(organization_id, mission_id: mission_id, enabled: true)}
  end

  defp load_automations(_mission_id) do
    # TODO: Load automation definitions
    # For now, return empty list - AutomationManager loads from DB
    {:ok, []}
  end

  defp load_transport_interfaces(organization_id, mission_id) do
    interfaces = Transports.list_interfaces(organization_id, mission_id)
    {:ok, interfaces}
  rescue
    e ->
      Logger.warning(
        "Failed to load transport interfaces for mission #{mission_id}: #{inspect(e)}"
      )

      {:ok, []}
  end

  defp load_links(organization_id, mission_id) do
    {:ok, Links.list_links_with_protocol_config(organization_id, mission_id)}
  rescue
    e ->
      Logger.warning("Failed to load links for mission #{mission_id}: #{inspect(e)}")
      {:ok, []}
  end

  defp load_bindings(organization_id, mission_id) do
    {:ok, Links.list_bindings(organization_id, mission_id)}
  rescue
    e ->
      Logger.warning("Failed to load bindings for mission #{mission_id}: #{inspect(e)}")
      {:ok, []}
  end

  defp load_active_selections(organization_id, mission_id) do
    {:ok, Links.list_active_selections(organization_id, mission_id)}
  rescue
    e ->
      Logger.warning("Failed to load active selections for mission #{mission_id}: #{inspect(e)}")

      {:ok, []}
  end

  defp load_channel_targets(organization_id, mission_id) do
    {:ok, Links.list_channel_targets_for_mission(organization_id, mission_id)}
  rescue
    e ->
      Logger.warning("Failed to load channel targets for mission #{mission_id}: #{inspect(e)}")

      {:ok, []}
  end

  defp validate_tc_stream_ids(routings, _interfaces, interface_vcids) do
    {vcid_by_target, vcid_defaults} = index_vcids(interface_vcids)

    cop1_routes =
      Enum.filter(routings, fn route ->
        TargetInterfaceEntity.allows_write?(route)
      end)

    missing_errors =
      Enum.flat_map(cop1_routes, fn route ->
        scid =
          case route.scid do
            scid when is_integer(scid) -> scid
            _ -> nil
          end

        vcid =
          Map.get(vcid_by_target, {route.interface_id, route.target_id}) ||
            Map.get(vcid_defaults, route.interface_id)

        []
        |> maybe_add_missing(route, :scid, scid)
        |> maybe_add_missing(route, :vcid, vcid)
      end)

    ambiguity_errors = ambiguous_route_errors(routings)

    errors = missing_errors ++ ambiguity_errors

    if errors == [] do
      :ok
    else
      {:error, {:invalid_tc_stream_ids, errors}}
    end
  end

  defp maybe_add_missing(errors, route, key, value) do
    if is_nil(value) do
      errors ++
        [
          %{
            target_id: route.target_id,
            interface_id: route.interface_id,
            reason: :"missing_#{key}"
          }
        ]
    else
      errors
    end
  end

  defp ambiguous_route_errors(routings) do
    routings
    |> Enum.filter(&TargetInterfaceEntity.allows_write?/1)
    |> Enum.group_by(& &1.target_id)
    |> Enum.flat_map(fn {target_id, routes} ->
      interface_ids =
        routes
        |> Enum.map(& &1.interface_id)
        |> Enum.uniq()

      if length(interface_ids) > 1 do
        [
          %{
            target_id: target_id,
            interface_ids: interface_ids,
            reason: :ambiguous_routes
          }
        ]
      else
        []
      end
    end)
  end

  defp index_vcids(nil), do: {%{}, %{}}
  defp index_vcids([]), do: {%{}, %{}}

  defp index_vcids(vcid_mappings) when is_list(vcid_mappings) do
    Enum.reduce(vcid_mappings, {%{}, %{}}, fn mapping, {by_target, defaults} ->
      interface_id = mapping.interface_id
      vcid = mapping.vcid
      target_id = mapping.target_id

      if is_binary(target_id) do
        {Map.put(by_target, {interface_id, target_id}, vcid), defaults}
      else
        {by_target, Map.put(defaults, interface_id, vcid)}
      end
    end)
  end
end
