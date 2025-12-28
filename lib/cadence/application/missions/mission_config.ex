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

  alias Cadence.Application.Interfaces.InterfaceQueries
  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Application.Targeting.TargetQueries

  require Logger

  @type t :: %__MODULE__{
          mission_id: String.t(),
          organization_id: String.t(),
          config_generation: integer(),
          mission: map(),
          interfaces: list(),
          targets: list(),
          packet_defs: map(),
          command_defs: map(),
          limit_defs: map(),
          derived_item_defs: map(),
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
    packet_defs: %{},
    command_defs: %{},
    limit_defs: %{},
    derived_item_defs: %{},
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
         packet_defs: packet_defs,
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

  defp load_packet_definitions(_mission_id) do
    # TODO: Load packet definitions from definition sets
    # For now, return empty map - PacketIdentifier ETS cache still works
    {:ok, %{}}
  end

  defp load_command_definitions(_mission_id) do
    # TODO: Load command definitions from definition sets
    # For now, return empty map - MetaCommandCache ETS still works
    {:ok, %{}}
  end

  defp load_limit_definitions(_mission_id) do
    # TODO: Load limit definitions
    # For now, return empty map - Limits.Cache ETS still works
    {:ok, %{}}
  end

  defp load_derived_items(_mission_id) do
    # TODO: Load derived item definitions
    # For now, return empty map - DerivedItems.Cache ETS still works
    {:ok, %{}}
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
end
