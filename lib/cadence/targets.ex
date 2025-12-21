defmodule Cadence.Targets do
  @moduledoc """
  The Targets context - boundary for target-related operations.

  This context handles:
  - Target CRUD operations
  - Circuit breaker state management
  - Target status tracking
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Targets.Target
  alias Cadence.Missions.Mission
  alias Cadence.Missions.MissionInstance
  alias Cadence.Commands.TargetPipelineSupervisor

  ## Target CRUD

  @doc """
  Returns the list of targets for a mission.
  """
  def list_targets(%Mission{id: mission_id}) do
    Target
    |> where([t], t.mission_id == ^mission_id)
    |> order_by([t], t.identifier)
    |> preload(definition_set: :database)
    |> Repo.all()
  end

  @doc """
  Gets a single target scoped to a mission.

  Raises `Ecto.NoResultsError` if the Target does not exist or doesn't belong to the mission.
  """
  def get_target!(id, mission_id) do
    Target
    |> where([t], t.id == ^id and t.mission_id == ^mission_id)
    |> Repo.one!()
  end

  @doc """
  Gets a single target scoped to a mission.

  Returns nil if the Target does not exist or doesn't belong to the mission.
  """
  def get_target(id, mission_id) do
    Target
    |> where([t], t.id == ^id and t.mission_id == ^mission_id)
    |> Repo.one()
  end

  @doc """
  Gets a single target by ID without mission scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where mission context is verified elsewhere (e.g., command pipeline, queue).
  """
  def get_target_unscoped(id), do: Repo.get(Target, id)

  @doc """
  Gets a single target by ID without mission scoping, raises if not found.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where mission context is verified elsewhere (e.g., command pipeline, queue).
  """
  def get_target_unscoped!(id), do: Repo.get!(Target, id)

  @doc """
  Gets a target by identifier within a mission.
  """
  def get_target_by_identifier(%Mission{id: mission_id}, identifier) do
    get_target_by_identifier(mission_id, identifier)
  end

  def get_target_by_identifier(mission_id, identifier) when is_binary(mission_id) do
    Target
    |> where([t], t.mission_id == ^mission_id and t.identifier == ^identifier)
    |> Repo.one()
  end

  @doc """
  Creates a target.

  If the mission is currently running, also starts the target's command pipeline.
  """
  def create_target(attrs \\ %{}) do
    with {:ok, target} <- do_create_target(attrs) do
      maybe_start_pipeline(target)
      {:ok, target}
    end
  end

  defp do_create_target(attrs) do
    %Target{}
    |> Target.changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_start_pipeline(%Target{} = target) do
    # Only start if mission is running
    case MissionInstance.whereis(target.mission_id) do
      nil ->
        # Mission not running, pipeline will start when mission starts
        :ok

      _pid ->
        case TargetPipelineSupervisor.start_pipeline(target.mission_id, target.id) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} ->
            require Logger
            Logger.warning("Failed to start pipeline for target #{target.id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  @doc """
  Updates a target.
  """
  def update_target(%Target{} = target, attrs) do
    target
    |> Target.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a target.

  If the mission is running, stops the target's command pipeline and cancels
  any pending queued commands for this target.
  """
  def delete_target(%Target{} = target) do
    # Cancel pending commands and stop pipeline before deleting
    cleanup_target_commands(target)
    maybe_stop_pipeline(target)
    Repo.delete(target)
  end

  defp cleanup_target_commands(%Target{} = target) do
    alias Cadence.Commands.{TargetQueue, QueueEntry}
    import Ecto.Query

    # Check if queue is running first to avoid exit errors
    case TargetQueue.whereis(target.mission_id, target.id) do
      nil ->
        # Queue not running, cancel via database directly
        from(e in QueueEntry,
          where: e.target_id == ^target.id,
          where: e.status == :pending
        )
        |> Repo.update_all(set: [status: :cancelled, updated_at: DateTime.utc_now()])

        :ok

      _pid ->
        TargetQueue.clear(target.mission_id, target.id)
    end
  end

  defp maybe_stop_pipeline(%Target{} = target) do
    case MissionInstance.whereis(target.mission_id) do
      nil ->
        # Mission not running, no pipeline to stop
        :ok

      _pid ->
        case TargetPipelineSupervisor.stop_pipeline(target.mission_id, target.id) do
          :ok -> :ok
          {:error, :not_found} -> :ok
          {:error, reason} ->
            require Logger
            Logger.warning("Failed to stop pipeline for target #{target.id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  ## Definition Set Assignment

  @doc """
  Assigns a definition set to a target.

  This determines which command/telemetry dictionary the target uses.
  """
  def assign_definition_set(%Target{} = target, definition_set_id) do
    target
    |> Target.assign_definition_set(definition_set_id)
    |> Repo.update()
  end

  @doc """
  Gets the definition_set_id for a target by mission_id and identifier.

  Returns nil if target not found or has no definition_set assigned.
  This is used by the telemetry pipeline to look up the correct dictionary.
  """
  def get_definition_set_id(mission_id, target_identifier)
      when is_binary(mission_id) and is_binary(target_identifier) do
    Target
    |> where([t], t.mission_id == ^mission_id and t.identifier == ^target_identifier)
    |> select([t], t.definition_set_id)
    |> Repo.one()
  end

  @doc """
  Gets the definition_set_id for a target by its ID.

  Returns nil if target not found or has no definition_set assigned.
  """
  def get_definition_set_id_by_target_id(target_id) when is_binary(target_id) do
    Target
    |> where([t], t.id == ^target_id)
    |> select([t], t.definition_set_id)
    |> Repo.one()
  end

  @doc """
  Gets a target with its definition_set preloaded.
  """
  def get_target_with_definition_set!(id) do
    Target
    |> Repo.get!(id)
    |> Repo.preload(:definition_set)
  end

  @doc """
  Returns all targets using a specific definition set.

  Useful for determining which targets are affected by a given
  command/telemetry database version.
  """
  def list_targets_by_definition_set(definition_set_id) do
    Target
    |> where([t], t.definition_set_id == ^definition_set_id)
    |> order_by([t], t.identifier)
    |> Repo.all()
  end

  ## Circuit Breaker Management

  @doc """
  Opens the circuit breaker for a target after command failures.
  """
  def open_circuit_breaker(%Target{} = target) do
    target
    |> Target.open_circuit_breaker()
    |> Repo.update()
  end

  @doc """
  Closes the circuit breaker, resetting failure count.
  """
  def close_circuit_breaker(%Target{} = target) do
    target
    |> Target.close_circuit_breaker()
    |> Repo.update()
  end

  @doc """
  Increments the failure count for a target's circuit breaker.

  If the failure count exceeds the threshold (default: 3), opens the circuit breaker.
  """
  def increment_circuit_breaker_failures(%Target{} = target, threshold \\ 3) do
    changeset = Target.increment_failures(target)

    with {:ok, updated_target} <- Repo.update(changeset) do
      if updated_target.circuit_breaker_failures >= threshold do
        open_circuit_breaker(updated_target)
      else
        {:ok, updated_target}
      end
    end
  end

  @doc """
  Checks if a target's circuit breaker is open.
  """
  def circuit_breaker_open?(%Target{circuit_breaker_status: status}) do
    status == "open"
  end
end
