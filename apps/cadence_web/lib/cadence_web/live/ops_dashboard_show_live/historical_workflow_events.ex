defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowEvents do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflow

  def open_request(socket, opts \\ []) do
    open_request_fn(opts).(socket)
  end

  def open_comparison_review_request(socket, params, opts \\ []) do
    open_comparison_review_request_fn(opts).(socket, params)
  end

  def record_stage(socket, params, opts \\ []) do
    # authz pending: Gate dashboard historical-data workflow mutations once RBAC exists.
    record_stage_fn(opts).(socket, params, opts)
  end

  def record_group_stage(socket, params, opts \\ []) do
    # authz pending: Gate dashboard historical-data workflow group mutations once RBAC exists.
    record_group_stage_fn(opts).(socket, params, opts)
  end

  def record_request(socket, params, opts \\ []) do
    # authz pending: Gate dashboard historical-data workflow requests once RBAC exists.
    record_request_fn(opts).(socket, params, opts)
  end

  def record_correction_request(socket, params, opts \\ []) do
    # authz pending: Gate dashboard historical-data workflow correction once RBAC exists.
    record_correction_request_fn(opts).(socket, params, opts)
  end

  def retry_job(socket, job_id, event_id, opts \\ []) do
    # authz pending: Gate dashboard historical-data workflow retry once RBAC exists.
    retry_job_fn(opts).(socket, job_id, event_id, opts)
  end

  def inspect_stale_replacement_job(socket, job_id, event_id, opts \\ []) do
    # authz pending: Gate dashboard stale replacement workflow inspection once RBAC exists.
    inspect_stale_replacement_job_fn(opts).(socket, job_id, event_id, opts)
  end

  def inspect_missing_replacement_job(socket, request_group_id, replacement_run_id, opts \\ []) do
    # authz pending: Gate dashboard missing replacement workflow inspection once RBAC exists.
    inspect_missing_replacement_job_fn(opts).(socket, request_group_id, replacement_run_id, opts)
  end

  def requeue_stale_replacement_job(socket, job_id, event_id, opts \\ []) do
    # authz pending: Gate dashboard stale replacement workflow requeue once RBAC exists.
    requeue_stale_replacement_job_fn(opts).(socket, job_id, event_id, opts)
  end

  def retry_group_failed_jobs(socket, request_group_id, event_id, opts \\ []) do
    # authz pending: Gate dashboard historical-data workflow group retry once RBAC exists.
    retry_group_failed_jobs_fn(opts).(socket, request_group_id, event_id, opts)
  end

  defp open_request_fn(opts),
    do: Keyword.get(opts, :open_request, &HistoricalWorkflow.open_request/1)

  defp open_comparison_review_request_fn(opts) do
    Keyword.get(
      opts,
      :open_comparison_review_request,
      &HistoricalWorkflow.open_comparison_review_request/2
    )
  end

  defp record_stage_fn(opts),
    do: Keyword.get(opts, :record_stage_event, &HistoricalWorkflow.record_stage/3)

  defp record_group_stage_fn(opts),
    do: Keyword.get(opts, :record_group_stage_event, &HistoricalWorkflow.record_group_stage/3)

  defp record_request_fn(opts),
    do: Keyword.get(opts, :record_request_event, &HistoricalWorkflow.record_request/3)

  defp record_correction_request_fn(opts) do
    Keyword.get(
      opts,
      :record_correction_request_event,
      &HistoricalWorkflow.record_correction_request/3
    )
  end

  defp retry_job_fn(opts),
    do: Keyword.get(opts, :retry_job_event, &HistoricalWorkflow.retry_job/4)

  defp inspect_stale_replacement_job_fn(opts) do
    Keyword.get(
      opts,
      :inspect_stale_replacement_job_event,
      &HistoricalWorkflow.inspect_stale_replacement_job/4
    )
  end

  defp inspect_missing_replacement_job_fn(opts) do
    Keyword.get(
      opts,
      :inspect_missing_replacement_job_event,
      &HistoricalWorkflow.inspect_missing_replacement_job/4
    )
  end

  defp requeue_stale_replacement_job_fn(opts) do
    Keyword.get(
      opts,
      :requeue_stale_replacement_job_event,
      &HistoricalWorkflow.requeue_stale_replacement_job/4
    )
  end

  defp retry_group_failed_jobs_fn(opts) do
    Keyword.get(
      opts,
      :retry_group_failed_jobs_event,
      &HistoricalWorkflow.retry_group_failed_jobs/4
    )
  end
end
