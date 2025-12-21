defmodule Cadence.Commands.TargetPipelineSupervisor do
  @moduledoc """
  DynamicSupervisor that manages all target command pipelines for a mission.

  When a mission starts, this supervisor:
  1. Loads all target configurations from the database
  2. Starts a TargetPipeline (Queue + Dispatcher) for each target
  3. Monitors pipeline health and handles crashes

  Each pipeline process is registered in the MissionRegistry with the key:
  `{:target_pipeline, mission_id, target_id}`

  ## Example

      # Started by MissionInstance supervision tree
      {:ok, pid} = TargetPipelineSupervisor.start_link(mission_id: mission_id)

      # Dynamically add a new target's pipeline
      TargetPipelineSupervisor.start_pipeline(mission_id, target_id)

      # Stop a target's pipeline
      TargetPipelineSupervisor.stop_pipeline(mission_id, target_id)
  """

  use DynamicSupervisor
  require Logger

  alias Cadence.{Missions, Targets}
  alias Cadence.Commands.TargetPipeline

  @registry Cadence.MissionRegistry

  ## Client API

  @doc """
  Starts the TargetPipelineSupervisor for a mission.

  Automatically loads and starts pipelines for all targets in the mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Starts a pipeline for a specific target.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_pipeline(mission_id, target_id) do
    # Use scoped get_target! to ensure target belongs to mission
    case Targets.get_target(target_id, mission_id) do
      nil ->
        {:error, :target_not_found}

      _target ->
        child_spec = {TargetPipeline, mission_id: mission_id, target_id: target_id}
        DynamicSupervisor.start_child(via_tuple(mission_id), child_spec)
    end
  end

  @doc """
  Stops a pipeline for a specific target.

  Returns `:ok` or `{:error, :not_found}`.
  """
  def stop_pipeline(mission_id, target_id) do
    case TargetPipeline.whereis(mission_id, target_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(via_tuple(mission_id), pid)
    end
  end

  @doc """
  Lists all running pipeline PIDs for a mission.
  """
  def list_pipelines(mission_id) do
    DynamicSupervisor.which_children(via_tuple(mission_id))
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end

  @doc """
  Restarts a pipeline (stop and start).
  """
  def restart_pipeline(mission_id, target_id) do
    with :ok <- stop_pipeline(mission_id, target_id),
         {:ok, pid} <- start_pipeline(mission_id, target_id) do
      {:ok, pid}
    end
  end

  @doc """
  Returns the PID of the supervisor for a mission.
  """
  def whereis(mission_id) do
    case Registry.lookup(@registry, {:target_pipeline_supervisor, mission_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting TargetPipelineSupervisor for mission #{mission_id}")

    # Start the supervisor first
    result = DynamicSupervisor.init(strategy: :one_for_one)

    # Then load and start all pipelines asynchronously
    # We do this async to avoid blocking the supervision tree startup
    Task.start(fn -> load_and_start_pipelines(mission_id) end)

    result
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:target_pipeline_supervisor, mission_id}}}
  end

  defp load_and_start_pipelines(mission_id) do
    Logger.info("Loading target pipelines for mission #{mission_id}")

    # Internal engine - use unscoped as mission context is verified through supervision tree
    mission = Missions.get_mission_unscoped!(mission_id)
    targets = Targets.list_targets(mission)

    Logger.info("Found #{length(targets)} target(s) for mission #{mission_id}")

    Enum.each(targets, fn target ->
      case start_pipeline(mission_id, target.id) do
        {:ok, pid} ->
          Logger.info(
            "Started TargetPipeline for target #{target.identifier} (#{target.id}), pid: #{inspect(pid)}"
          )

        {:error, {:already_started, pid}} ->
          Logger.debug(
            "TargetPipeline for target #{target.identifier} (#{target.id}) already started, pid: #{inspect(pid)}"
          )

        {:error, reason} ->
          Logger.error(
            "Failed to start TargetPipeline for target #{target.identifier} (#{target.id}): #{inspect(reason)}"
          )
      end
    end)
  end
end
