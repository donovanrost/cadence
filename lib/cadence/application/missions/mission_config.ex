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
  alias Cadence.Repo
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Telemetry.Database.DerivedItem
  alias Cadence.Telemetry.Packet.PacketDefinition

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
          automations: list()
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
    automations: []
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
         :ok <- validate_tc_stream_ids(target_interface_routings, interfaces),
         {:ok, queue_snapshots} <- load_queue_snapshots(mission_id, targets),
         {:ok, packet_catalog_defs} <- load_packet_catalog_defs(mission_id, targets),
         {:ok, packet_defs} <- load_packet_definitions(mission_id),
         {:ok, command_defs} <- load_command_definitions(mission_id),
         {:ok, limit_defs} <- load_limit_definitions(mission_id),
         {:ok, derived_item_defs} <- load_derived_items(mission_id),
         {:ok, alarm_rules} <- load_alarm_rules(mission_id),
         {:ok, automations} <- load_automations(mission_id) do
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
         automations: automations
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

  defp load_command_definitions(_mission_id) do
    # TODO: Load command definitions from definition sets
    # For now, return empty map - MetaCommandCache ETS still works
    {:ok, %{}}
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

  defp load_alarm_rules(_mission_id) do
    # TODO: Load alarm rules
    # For now, return empty list - RuleCache ETS still works
    {:ok, []}
  end

  defp load_automations(_mission_id) do
    # TODO: Load automation definitions
    # For now, return empty list - AutomationManager loads from DB
    {:ok, []}
  end

  defp validate_tc_stream_ids(routings, interfaces) do
    interfaces_by_id = Map.new(interfaces, fn interface -> {interface.id, interface} end)

    cop1_routes =
      Enum.filter(routings, fn route ->
        TargetInterfaceEntity.allows_write?(route) and
          cop1_enabled_interface?(interfaces_by_id, route.interface_id)
      end)

    errors =
      cop1_routes
      |> Enum.group_by(& &1.interface_id)
      |> Enum.flat_map(fn {interface_id, routes} ->
        {missing_errors, entries} = collect_stream_ids(routes)
        conflict_errors = conflicting_stream_ids(entries, interface_id)
        missing_errors ++ conflict_errors
      end)

    if errors == [] do
      :ok
    else
      {:error, {:invalid_tc_stream_ids, errors}}
    end
  end

  defp collect_stream_ids(routes) do
    Enum.reduce(routes, {[], []}, fn route, {errors, entries} ->
      stream_id = normalize_stream_id(route.tc_stream_id)

      if is_nil(stream_id) do
        error = %{
          target_id: route.target_id,
          interface_id: route.interface_id,
          reason: :missing_tc_stream_id
        }

        {errors ++ [error], entries}
      else
        {errors, entries ++ [%{stream_id: stream_id, target_id: route.target_id}]}
      end
    end)
  end

  defp conflicting_stream_ids(entries, interface_id) do
    entries
    |> Enum.group_by(& &1.stream_id)
    |> Enum.flat_map(fn {stream_id, grouped} ->
      target_ids = grouped |> Enum.map(& &1.target_id) |> Enum.uniq()

      if length(target_ids) > 1 do
        [
          %{
            interface_id: interface_id,
            tc_stream_id: stream_id,
            target_ids: target_ids,
            reason: :conflicting_tc_stream_ids
          }
        ]
      else
        []
      end
    end)
  end

  defp normalize_stream_id(nil), do: nil
  defp normalize_stream_id(""), do: nil
  defp normalize_stream_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_stream_id(value) when is_binary(value), do: value
  defp normalize_stream_id(_value), do: nil

  defp cop1_enabled_interface?(interfaces_by_id, interface_id) do
    case Map.get(interfaces_by_id, interface_id) do
      nil -> false
      interface -> COP1Application.enabled?(interface)
    end
  end
end
