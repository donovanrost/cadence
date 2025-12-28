defmodule Cadence.Runtime.Commands.TargetPipeline do
  @moduledoc """
  Supervisor for a single target's command queue and dispatcher.

  Each target gets its own TargetPipeline which supervises:
  - TargetQueue - manages command ordering and scheduling
  - TargetDispatcher - handles command execution

  This 1:1 relationship ensures:
  - Clean separation of concerns
  - Per-target command serialization (safety)
  - Cross-target parallelism (performance)
  - Isolated failure domains

  ## Data Plane Architecture

  This supervisor receives domain entities (mission, target) from its parent
  supervisor and injects them into child GenServers. No database calls happen
  during init - the entities ARE the configuration.

  ## Example

      # Started by TargetPipelineSupervisor with entities
      {:ok, pid} = TargetPipeline.start_link(mission: mission, target: target)

      # Find the pipeline process
      pid = TargetPipeline.whereis(mission_id, target_id)
  """

  use Supervisor

  require Logger

  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Runtime.Commands.{TargetDispatcher, TargetQueue}

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the pipeline for a target.

  Accepts either:
  - Entity-based: `mission: mission_entity, target: target_entity` (preferred, no DB calls)
  - ID-based: `mission_id: id, target_id: id` (legacy, makes DB calls)
  """
  def start_link(opts) do
    {mission, target} = extract_mission_and_target(opts)

    Supervisor.start_link(__MODULE__, {mission, target}, name: via_tuple(mission.id, target.id))
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(mission_id, target_id) do
    {:via, Registry, {@registry, {:target_pipeline, mission_id, target_id}}}
  end

  @doc """
  Returns the PID of a pipeline by mission_id and target_id.
  """
  def whereis(mission_id, target_id) do
    case Registry.lookup(@registry, {:target_pipeline, mission_id, target_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  ## Supervisor Callbacks

  @impl true
  def init({%Mission{} = mission, %Target{} = target}) do
    Logger.info(
      "Starting TargetPipeline for mission_id=#{mission.id}, target=#{target.identifier} (#{target.id})"
    )

    children = [
      # Queue must start before Dispatcher since Dispatcher queries Queue
      # Pass entities directly - no DB lookups needed
      {TargetQueue, mission: mission, target: target},
      {TargetDispatcher, mission: mission, target: target}
    ]

    # one_for_one: if queue crashes, restart just queue
    # if dispatcher crashes, restart just dispatcher
    # They can recover independently using the injected entities
    Supervisor.init(children, strategy: :one_for_one)
  end

  ## Private Functions

  # Extract mission and target from opts, supporting both entity and ID-based startup
  defp extract_mission_and_target(opts) do
    case {Keyword.get(opts, :mission), Keyword.get(opts, :target)} do
      {%Mission{} = mission, %Target{} = target} ->
        # Entity-based startup (preferred) - no DB calls
        {mission, target}

      {nil, nil} ->
        # Legacy ID-based startup - makes DB calls
        mission_id = Keyword.fetch!(opts, :mission_id)
        target_id = Keyword.fetch!(opts, :target_id)

        Logger.warning(
          "TargetPipeline started with IDs instead of entities. " <>
            "Consider passing entities to avoid DB calls."
        )

        mission = Cadence.Missions.get_mission!(mission_id)
        target = Cadence.Targets.get_target_with_definition_set!(target_id)

        {mission, target}

      _ ->
        raise ArgumentError,
              "TargetPipeline requires either (mission: entity, target: entity) or (mission_id: id, target_id: id)"
    end
  end
end
