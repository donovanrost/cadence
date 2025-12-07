defmodule Cadence.Procedures.Workers.OrphanedExecutionCleanupWorker do
  @moduledoc """
  Periodic Oban worker that detects and cleans up orphaned procedure executions.

  An execution becomes orphaned when:
  - Its `ExecutionProcess` crashes without properly transitioning status
  - The node restarts while executions were running
  - The status is `:pausing` but the process is no longer alive

  ## Detection Strategy

  1. Query all executions in non-terminal states (pending, running, pausing, paused)
  2. For each execution, check if there's a live `ExecutionProcess`
  3. If no live process and execution is stale (updated > threshold ago), mark as orphaned

  ## Recovery Actions

  - `:pending` - Can be restarted
  - `:running` - Mark as failed with "Process died unexpectedly"
  - `:pausing` - Mark as failed with "Pausing interrupted"
  - `:paused` - Leave as-is (valid state, can be resumed manually)

  ## Configuration

  This worker runs every minute by default (configurable via Cron plugin).
  The staleness threshold is 2 minutes.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 60]

  require Logger

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Procedures.ProcedureExecution
  alias Cadence.Procedures.Engine.ExecutionProcess

  # How long an execution must be stale before considered orphaned (2 minutes)
  @staleness_threshold_seconds 120

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("OrphanedExecutionCleanupWorker: Starting cleanup check")

    orphaned = find_orphaned_executions()

    if Enum.any?(orphaned) do
      Logger.info("OrphanedExecutionCleanupWorker: Found #{length(orphaned)} orphaned executions")
      Enum.each(orphaned, &cleanup_orphaned_execution/1)
    end

    :ok
  end

  @doc """
  Finds executions that appear to be orphaned.

  Returns list of executions in non-terminal states where:
  - No live ExecutionProcess exists
  - Last updated more than staleness threshold ago
  """
  def find_orphaned_executions do
    threshold = DateTime.add(DateTime.utc_now(), -@staleness_threshold_seconds, :second)

    # Query all non-terminal executions that haven't been updated recently
    query =
      from(e in ProcedureExecution,
        where: e.status in [:pending, :running, :pausing],
        where: e.updated_at < ^threshold,
        preload: [:procedure]
      )

    Repo.all(query)
    |> Enum.filter(&orphaned?/1)
  end

  # Check if an execution is orphaned (no live process)
  defp orphaned?(execution) do
    case ExecutionProcess.whereis(execution.id) do
      nil -> true
      pid -> not Process.alive?(pid)
    end
  end

  defp cleanup_orphaned_execution(execution) do
    Logger.warning(
      "OrphanedExecutionCleanupWorker: Cleaning up orphaned execution #{execution.id} " <>
        "(status: #{execution.status}, procedure: #{execution.procedure.name})"
    )

    case execution.status do
      :pending ->
        # Pending executions that never started - mark as failed
        mark_failed(execution, "Execution never started - process died before start")

      :running ->
        # Running execution with dead process - mark as failed
        mark_failed(execution, "Execution interrupted - process died unexpectedly")

      :pausing ->
        # Pausing got stuck - mark as failed
        mark_failed(execution, "Pause interrupted - process died while pausing")
    end
  end

  defp mark_failed(execution, error_message) do
    # Build a minimal result structure for persist_dag_result
    result = %{
      completed_steps: execution.completed_steps || [],
      skipped_steps: execution.skipped_steps || [],
      failed_steps: execution.failed_steps || [],
      blocked_steps: execution.blocked_steps || [],
      step_results: execution.step_results || %{}
    }

    # Update with error_message override
    attrs = %{
      status: :failed,
      completed_at: DateTime.utc_now(),
      error_message: error_message,
      completed_steps: result.completed_steps,
      skipped_steps: result.skipped_steps,
      failed_steps: result.failed_steps,
      blocked_steps: result.blocked_steps,
      step_results: result.step_results
    }

    case Cadence.Procedures.update_execution_status(execution, attrs) do
      {:ok, updated} ->
        # Broadcast status change
        topic = "procedure:#{execution.id}"
        Phoenix.PubSub.broadcast(Cadence.PubSub, topic, {:status_changed, :failed, updated})

        Logger.info("OrphanedExecutionCleanupWorker: Marked execution #{execution.id} as failed")

      {:error, changeset} ->
        Logger.error(
          "OrphanedExecutionCleanupWorker: Failed to update execution #{execution.id}: " <>
            "#{inspect(changeset.errors)}"
        )
    end
  end
end
