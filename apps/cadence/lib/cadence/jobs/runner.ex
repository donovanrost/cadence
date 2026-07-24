defmodule Cadence.Jobs.Runner do
  @moduledoc """
  Composition-boundary router for durable jobs.

  The platform-owned `Cadence.Jobs` queue has no domain dependencies. This
  runner is started by the jobs worker and is the one explicit place that maps
  a durable job type to the public API owned by the executing context.
  """

  alias Cadence.Catalog
  alias Cadence.Control.DerivedTelemetry
  alias Cadence.Dashboards.{ManagedQuestDBProvisioningJobs, TSDBBackendLifecycleJobs}
  alias Cadence.Jobs
  alias Cadence.Jobs.Job
  alias Cadence.Limits

  alias Cadence.Projections.{
    DerivedTelemetryLatestValues,
    MissionEvents,
    TelemetryLatestLimitStates,
    TelemetryLatestValues
  }

  alias Cadence.Replay
  alias Cadence.Telemetry.DataManagement, as: TelemetryDataManagement

  @spec run_job(binary()) :: {:ok, Job.t()} | {:error, term()}
  def run_job(job_id) when is_binary(job_id) do
    case Jobs.fetch_job(job_id) do
      {:ok, %Job{status: :running} = job} ->
        Jobs.record_execution_result(job, safe_dispatch(job))

      {:ok, %Job{} = job} ->
        Jobs.record_execution_result(job, {:error, {:job_not_running, job.status}})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch(%Job{job_type: :replay_telemetry_scope, run_id: replay_run_id}) do
    Replay.execute_enqueued_run(replay_run_id)
  end

  defp dispatch(%Job{job_type: :telemetry_latest_value_rebuild, run_id: rebuild_run_id}) do
    TelemetryLatestValues.execute_enqueued_run(rebuild_run_id)
  end

  defp dispatch(%Job{job_type: :derived_telemetry_evaluation, run_id: derived_run_id}) do
    DerivedTelemetry.execute_enqueued_run(derived_run_id)
  end

  defp dispatch(%Job{job_type: :derived_telemetry_latest_value_rebuild, run_id: rebuild_run_id}) do
    DerivedTelemetryLatestValues.execute_enqueued_run(rebuild_run_id)
  end

  defp dispatch(%Job{job_type: :telemetry_limit_evaluation, run_id: limit_run_id}) do
    Limits.execute_enqueued_run(limit_run_id)
  end

  defp dispatch(%Job{job_type: :telemetry_latest_limit_state_refresh, run_id: rebuild_run_id}) do
    TelemetryLatestLimitStates.execute_enqueued_refresh_run(rebuild_run_id)
  end

  defp dispatch(%Job{job_type: :telemetry_latest_limit_state_rebuild, run_id: rebuild_run_id}) do
    TelemetryLatestLimitStates.execute_enqueued_run(rebuild_run_id)
  end

  defp dispatch(%Job{job_type: :mission_event_rebuild, run_id: rebuild_run_id}) do
    MissionEvents.execute_enqueued_run(rebuild_run_id)
  end

  defp dispatch(%Job{job_type: :catalog_import_run, run_id: import_run_id}) do
    Catalog.execute_enqueued_run(import_run_id)
  end

  defp dispatch(%Job{job_type: :telemetry_historical_data_workflow, run_id: workflow_run_id}) do
    TelemetryDataManagement.execute_enqueued_historical_data_workflow(workflow_run_id)
  end

  defp dispatch(%Job{job_type: :managed_questdb_provisioning, run_id: provisioning_run_id}) do
    ManagedQuestDBProvisioningJobs.execute_enqueued_run(provisioning_run_id)
  end

  defp dispatch(%Job{job_type: :dashboard_tsdb_backend_lifecycle, run_id: lifecycle_run_id}) do
    TSDBBackendLifecycleJobs.execute_enqueued_run(lifecycle_run_id)
  end

  defp safe_dispatch(%Job{} = job) do
    dispatch(job)
  rescue
    exception ->
      {:error, {:exception, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end
end
