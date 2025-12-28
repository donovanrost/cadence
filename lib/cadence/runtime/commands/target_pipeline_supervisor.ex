defmodule Cadence.Runtime.Commands.TargetPipelineSupervisor do
  @moduledoc """
  Supervisor that manages all target command pipelines for a mission.

  ## Data Plane Architecture

  This supervisor loads target domain entities ONCE at startup and injects
  them into GenServers. No database calls happen during runtime operation.

  When a mission starts, this supervisor:
  1. Loads all target entities with definition_sets preloaded
  2. Starts a TargetPipeline (Queue + Dispatcher) for each target
  3. Monitors pipeline health and handles crashes
  4. Subscribes to config change events for hot reload

  Each pipeline process is registered in the MissionRegistry with the key:
  `{:target_pipeline, mission_id, target_id}`

  ## Hot Reload

  The supervisor subscribes to `targets:{mission_id}` and handles:
  - `:target_changed, :created` - Start a new pipeline
  - `:target_changed, :updated` - Restart pipeline with new config
  - `:target_changed, :deleted` - Stop the pipeline

  ## Example

      # Started by MissionInstance supervision tree
      {:ok, pid} = TargetPipelineSupervisor.start_link(mission_id: mission_id)

      # Dynamically add a new target's pipeline (with domain entity)
      TargetPipelineSupervisor.start_pipeline(mission_id, target_entity)

      # Stop a target's pipeline
      TargetPipelineSupervisor.stop_pipeline(mission_id, target_id)
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Missions
  alias Cadence.Runtime.Commands.TargetPipeline
  alias Cadence.Targets

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [:mission_id, :mission, :dynamic_sup, targets: %{}]
  end

  ## Client API

  @doc """
  Starts the TargetPipelineSupervisor for a mission.

  Automatically loads and starts pipelines for all targets in the mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Starts a pipeline for a specific target using its domain entity.

  The entity should be fully loaded with definition_set. No database lookups
  are performed - the entity IS the configuration.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_pipeline(mission_id, %Target{} = target) do
    GenServer.call(via_tuple(mission_id), {:start_pipeline, target})
  end

  @doc """
  Starts a pipeline for a specific target by ID, loading it from the database.

  This is a convenience function for cases where the entity is not
  already loaded. For hot reload scenarios, prefer `start_pipeline/2`
  with a pre-loaded entity.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def start_pipeline_by_id(mission_id, target_id) do
    case Targets.get_target_with_definition_set(target_id) do
      {:ok, target} ->
        start_pipeline(mission_id, target)

      {:error, :not_found} ->
        {:error, :target_not_found}
    end
  end

  @doc """
  Stops a pipeline for a specific target.

  Returns `:ok` or `{:error, :not_found}`.
  """
  def stop_pipeline(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id), {:stop_pipeline, target_id})
  end

  @doc """
  Lists all running pipeline PIDs for a mission.
  """
  def list_pipelines(mission_id) do
    GenServer.call(via_tuple(mission_id), :list_pipelines)
  end

  @doc """
  Restarts a pipeline with a new entity (stop and start).

  Used for hot reload when configuration changes.
  """
  def restart_pipeline(mission_id, %Target{} = target) do
    GenServer.call(via_tuple(mission_id), {:restart_pipeline, target})
  end

  @doc """
  Restarts a pipeline by ID, reloading from database.

  Convenience function for manual restarts.
  """
  def restart_pipeline_by_id(mission_id, target_id) do
    case Targets.get_target_with_definition_set(target_id) do
      {:ok, target} ->
        restart_pipeline(mission_id, target)

      {:error, :not_found} ->
        {:error, :target_not_found}
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

    # Start a DynamicSupervisor for managing pipeline children
    {:ok, dynamic_sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    # Subscribe to target changes for hot reload
    topic = "targets:#{mission_id}"
    Phoenix.PubSub.subscribe(Cadence.PubSub, topic)
    Logger.debug("Subscribed to #{topic} for pipeline hot reload")

    # Load mission entity once
    mission = Missions.get_mission!(mission_id)

    state = %State{
      mission_id: mission_id,
      mission: mission,
      dynamic_sup: dynamic_sup,
      targets: %{}
    }

    # Load and start all pipelines asynchronously
    send(self(), :load_pipelines)

    {:ok, state}
  end

  @impl true
  def handle_call({:start_pipeline, %Target{} = target}, _from, state) do
    case do_start_pipeline(target, state) do
      {:ok, pid} ->
        # Store the target entity for restart
        targets = Map.put(state.targets, target.id, target)
        {:reply, {:ok, pid}, %{state | targets: targets}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:stop_pipeline, target_id}, _from, state) do
    result = do_stop_pipeline(target_id, state)
    targets = Map.delete(state.targets, target_id)
    {:reply, result, %{state | targets: targets}}
  end

  def handle_call(:list_pipelines, _from, state) do
    children =
      DynamicSupervisor.which_children(state.dynamic_sup)
      |> Enum.map(fn {_, pid, _, _} -> pid end)

    {:reply, children, state}
  end

  def handle_call({:restart_pipeline, %Target{} = target}, _from, state) do
    case do_restart_pipeline(target, state) do
      {:ok, pid} ->
        # Update stored target entity
        targets = Map.put(state.targets, target.id, target)
        {:reply, {:ok, pid}, %{state | targets: targets}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info(:load_pipelines, state) do
    new_state = load_and_start_pipelines(state)
    {:noreply, new_state}
  end

  # Hot reload: Target changed (created, updated, deleted, etc.)
  def handle_info({:target_changed, event_type, %Target{} = target}, state) do
    new_state = handle_target_event(event_type, target, state)
    {:noreply, new_state}
  end

  # Ignore unhandled messages
  def handle_info(msg, state) do
    Logger.debug("TargetPipelineSupervisor received unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down TargetPipelineSupervisor for mission #{state.mission_id}")

    # DynamicSupervisor traps exits and ignores EXIT signals from non-child processes.
    # We must explicitly stop it to ensure children terminate gracefully.
    if state.dynamic_sup && Process.alive?(state.dynamic_sup) do
      Supervisor.stop(state.dynamic_sup, :shutdown, 5_000)
    end

    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:target_pipeline_supervisor, mission_id}}}
  end

  defp handle_target_event(:created, target, state) do
    Logger.info(
      "Hot reload: Starting new pipeline for target #{target.identifier} (#{target.id})"
    )

    case do_start_pipeline(target, state) do
      {:ok, pid} ->
        Logger.info("Hot reload: Pipeline for #{target.identifier} started, pid: #{inspect(pid)}")
        targets = Map.put(state.targets, target.id, target)
        %{state | targets: targets}

      {:error, reason} ->
        Logger.error(
          "Hot reload: Failed to start pipeline for #{target.identifier}: #{inspect(reason)}"
        )

        state
    end
  end

  defp handle_target_event(:deleted, target, state) do
    Logger.info("Hot reload: Stopping pipeline for target #{target.identifier} (#{target.id})")

    case do_stop_pipeline(target.id, state) do
      :ok ->
        Logger.info("Hot reload: Pipeline for #{target.identifier} stopped")
        targets = Map.delete(state.targets, target.id)
        %{state | targets: targets}

      {:error, :not_found} ->
        Logger.debug("Hot reload: Pipeline for #{target.identifier} was not running")
        state
    end
  end

  defp handle_target_event(_event_type, target, state) do
    # For updates (online, offline, circuit_breaker, etc.), restart the pipeline
    Logger.info("Hot reload: Restarting pipeline for target #{target.identifier} (#{target.id})")

    case do_restart_pipeline(target, state) do
      {:ok, pid} ->
        Logger.info(
          "Hot reload: Pipeline for #{target.identifier} restarted, pid: #{inspect(pid)}"
        )

        targets = Map.put(state.targets, target.id, target)
        %{state | targets: targets}

      {:error, :not_found} ->
        # Pipeline wasn't running, start it
        Logger.info("Hot reload: Pipeline for #{target.identifier} not running, starting it")

        case do_start_pipeline(target, state) do
          {:ok, pid} ->
            Logger.info(
              "Hot reload: Pipeline for #{target.identifier} started, pid: #{inspect(pid)}"
            )

            targets = Map.put(state.targets, target.id, target)
            %{state | targets: targets}

          {:error, reason} ->
            Logger.error(
              "Hot reload: Failed to start pipeline for #{target.identifier}: #{inspect(reason)}"
            )

            state
        end

      {:error, reason} ->
        Logger.error(
          "Hot reload: Failed to restart pipeline for #{target.identifier}: #{inspect(reason)}"
        )

        state
    end
  end

  defp do_start_pipeline(%Target{} = target, state) do
    if target.mission_id != state.mission_id do
      {:error, :target_not_in_mission}
    else
      child_spec = {TargetPipeline, mission: state.mission, target: target}
      DynamicSupervisor.start_child(state.dynamic_sup, child_spec)
    end
  end

  defp do_stop_pipeline(target_id, state) do
    case TargetPipeline.whereis(state.mission_id, target_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(state.dynamic_sup, pid)
    end
  end

  defp do_restart_pipeline(%Target{} = target, state) do
    with :ok <- do_stop_pipeline(target.id, state) do
      do_start_pipeline(target, state)
    end
  end

  defp load_and_start_pipelines(state) do
    Logger.info("Loading target pipelines for mission #{state.mission_id}")

    # Load all targets with definition_sets preloaded - this is the ONLY DB call
    targets = Targets.list_targets(state.mission_id)

    # Load definition_sets for each target
    targets_with_ds =
      Enum.map(targets, fn target ->
        case Targets.get_target_with_definition_set(target.id) do
          {:ok, t} -> t
          {:error, _} -> target
        end
      end)

    Logger.info("Found #{length(targets_with_ds)} target(s) for mission #{state.mission_id}")

    # Start pipelines and collect targets map
    targets_map =
      Enum.reduce(targets_with_ds, %{}, fn target, acc ->
        case do_start_pipeline(target, state) do
          {:ok, pid} ->
            Logger.info(
              "Started TargetPipeline for target #{target.identifier} (#{target.id}), pid: #{inspect(pid)}"
            )

            Map.put(acc, target.id, target)

          {:error, {:already_started, pid}} ->
            Logger.debug(
              "TargetPipeline for target #{target.identifier} (#{target.id}) already started, pid: #{inspect(pid)}"
            )

            Map.put(acc, target.id, target)

          {:error, reason} ->
            Logger.error(
              "Failed to start TargetPipeline for target #{target.identifier} (#{target.id}): #{inspect(reason)}"
            )

            acc
        end
      end)

    %{state | targets: targets_map}
  end
end
