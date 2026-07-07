defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenter do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowRequestDefaults
  }

  @type action_outcome :: HistoricalWorkflowActionOutcome.t()
  @type request_defaults :: HistoricalWorkflowRequestDefaults.t()

  def action_outcome(action, status, context \\ %{})

  def action_outcome(:stage_transition, {:ok, job_result}, context) do
    stage = Map.get(context, :stage)
    {kind, message} = workflow_flash(stage, job_result)

    outcome(
      action: :stage_transition,
      status: status_from_kind(kind),
      kind: kind,
      job_id: job_id_from_result(job_result),
      message: message
    )
    |> put_action_context(context)
    |> Map.put(:reason, stage_success_reason(job_result))
    |> Map.put(:stage, stage)
  end

  def action_outcome(:stage_transition, {:error, reason}, context) do
    stage = Map.get(context, :stage)

    outcome(
      action: :stage_transition,
      status: :error,
      kind: :error,
      reason: "stage_transition_failed",
      stage: stage,
      error: reason,
      message:
        workflow_failure_message(
          "Failed to record historical data workflow #{stage}",
          reason
        )
    )
    |> put_action_context(context)
  end

  def action_outcome(:stage_transition, :unconfirmed, context) do
    stage = Map.get(context, :stage)

    outcome(
      action: :stage_transition,
      status: :blocked,
      kind: :error,
      reason: "confirmation_required",
      stage: stage,
      message: "Confirm the historical data workflow #{stage} transition before recording it."
    )
    |> put_action_context(context)
  end

  def action_outcome(:group_stage_transition, {:ok, events, job_results}, context) do
    stage = Map.get(context, :stage)
    {kind, message} = group_flash(stage, events, job_results)

    outcome(
      action: :group_stage_transition,
      status: group_status(stage, job_results, kind),
      kind: kind,
      reason: group_success_reason(stage, job_results),
      stage: stage,
      count: length(events),
      queued_jobs: group_queued_job_count(stage, job_results),
      failed_jobs: group_dispatch_failed_count(stage, job_results),
      message: message
    )
    |> put_result_events(events)
    |> put_action_context(context)
  end

  def action_outcome(
        :group_stage_transition,
        {:no_eligible, request_group_id, failed_stage},
        _context
      ) do
    outcome(
      action: :group_stage_transition,
      status: :no_op,
      kind: :info,
      reason: "no_eligible_group_items",
      stage: failed_stage,
      request_group_id: request_group_id,
      message: no_eligible_group_flash(request_group_id, failed_stage)
    )
  end

  def action_outcome(:group_stage_transition, {:error, reason}, context) do
    stage = Map.get(context, :stage)

    outcome(
      action: :group_stage_transition,
      status: :error,
      kind: :error,
      reason: "group_stage_transition_failed",
      stage: stage,
      error: reason,
      message:
        workflow_failure_message(
          "Failed to record historical data workflow group #{stage}",
          reason
        )
    )
    |> put_action_context(context)
  end

  def action_outcome(:group_stage_transition, :unconfirmed, context) do
    stage = Map.get(context, :stage)

    outcome(
      action: :group_stage_transition,
      status: :blocked,
      kind: :error,
      reason: "confirmation_required",
      stage: stage,
      message:
        "Confirm the historical data workflow group #{stage} transition before recording it."
    )
    |> put_action_context(context)
  end

  def action_outcome(:request, {:ok, events}, context) do
    outcome(
      action: :request,
      status: :ok,
      kind: :info,
      reason: request_success_reason(events),
      count: length(events),
      message: request_flash(events)
    )
    |> put_result_events(events)
    |> put_action_context(context)
  end

  def action_outcome(:request, {:error, reason}, context) do
    outcome(
      action: :request,
      status: :error,
      kind: :error,
      reason: "request_failed",
      error: reason,
      message:
        workflow_failure_message(
          "Failed to record historical data workflow request",
          reason
        )
    )
    |> put_action_context(context)
  end

  def action_outcome(:request, :unconfirmed, context) do
    outcome(
      action: :request,
      status: :blocked,
      kind: :error,
      reason: "confirmation_required",
      message: "Confirm the historical data workflow request before recording it."
    )
    |> put_action_context(context)
  end

  def action_outcome(:correction_request, {:ok, event}, context) do
    outcome(
      action: :correction_request,
      status: :ok,
      kind: :info,
      reason: "correction_request_recorded",
      message: "Corrected historical data workflow request recorded."
    )
    |> put_result_events([event])
    |> put_action_context(context)
  end

  def action_outcome(:correction_request, {:error, reason}, context) do
    outcome(
      action: :correction_request,
      status: :error,
      kind: :error,
      reason: "correction_request_failed",
      error: reason,
      message:
        workflow_failure_message(
          "Failed to record corrected historical data workflow request",
          reason
        )
    )
    |> put_action_context(context)
  end

  def action_outcome(:correction_request, :unconfirmed, context) do
    outcome(
      action: :correction_request,
      status: :blocked,
      kind: :error,
      reason: "confirmation_required",
      message: "Confirm the corrected historical data workflow request before recording it."
    )
    |> put_action_context(context)
  end

  def action_outcome(:retry_job, {:ok, retried_job, retry_event}, context) do
    job_id = Map.get(retried_job, :job_id)

    outcome(
      action: :retry_job,
      status: :ok,
      kind: :info,
      reason: "retry_job_recorded",
      job_id: job_id,
      message: "Retried historical data workflow job #{job_id} and recorded retry event."
    )
    |> put_result_events([retry_event])
    |> put_action_context(context)
  end

  def action_outcome(:retry_job, {:error, reason}, context) do
    outcome(
      action: :retry_job,
      status: :error,
      kind: :error,
      reason: "retry_job_failed",
      error: reason,
      message: workflow_failure_message("Failed to retry historical data workflow job", reason)
    )
    |> put_action_context(context)
  end

  def action_outcome(:stale_replacement_job_inspection, {:ok, inspection_event}, context) do
    outcome(
      action: :stale_replacement_job_inspection,
      status: :ok,
      kind: :info,
      reason: "stale_replacement_job_inspection_recorded",
      message: "Recorded stale replacement job inspection."
    )
    |> put_result_events([inspection_event])
    |> put_action_context(context)
  end

  def action_outcome(:stale_replacement_job_inspection, {:error, reason}, context) do
    outcome(
      action: :stale_replacement_job_inspection,
      status: :error,
      kind: :error,
      reason: "stale_replacement_job_inspection_failed",
      error: reason,
      message: workflow_failure_message("Failed to inspect stale replacement job", reason)
    )
    |> put_action_context(context)
  end

  def action_outcome(:missing_replacement_job_inspection, {:ok, inspection_event}, context) do
    outcome(
      action: :missing_replacement_job_inspection,
      status: :ok,
      kind: :info,
      reason: "missing_replacement_job_inspection_recorded",
      message: "Recorded missing replacement job inspection."
    )
    |> put_result_events([inspection_event])
    |> put_action_context(context)
  end

  def action_outcome(:missing_replacement_job_inspection, {:error, reason}, context) do
    outcome(
      action: :missing_replacement_job_inspection,
      status: :error,
      kind: :error,
      reason: "missing_replacement_job_inspection_failed",
      error: reason,
      message: workflow_failure_message("Failed to inspect missing replacement job", reason)
    )
    |> put_action_context(context)
  end

  def action_outcome(:stale_replacement_job_requeue, {:ok, requeued_job, requeue_event}, context) do
    job_id = Map.get(requeued_job, :job_id)

    outcome(
      action: :stale_replacement_job_requeue,
      status: :ok,
      kind: :info,
      reason: "stale_replacement_job_requeue_recorded",
      job_id: job_id,
      message: "Requeued stale replacement job #{job_id} and recorded audit event."
    )
    |> put_result_events([requeue_event])
    |> put_action_context(context)
  end

  def action_outcome(:stale_replacement_job_requeue, {:error, reason}, context) do
    outcome(
      action: :stale_replacement_job_requeue,
      status: :error,
      kind: :error,
      reason: "stale_replacement_job_requeue_failed",
      error: reason,
      message: workflow_failure_message("Failed to requeue stale replacement job", reason)
    )
    |> put_action_context(context)
  end

  def action_outcome(:retry_group_failed_jobs, {:ok, summary}, context) do
    outcome(
      action: :retry_group_failed_jobs,
      status: group_retry_status(summary),
      kind: group_retry_kind(summary),
      reason: group_retry_reason(summary),
      retried: Map.get(summary, :retried),
      retry_nonretryable: Map.get(summary, :nonretryable),
      retry_skipped: Map.get(summary, :skipped),
      retry_errors: Map.get(summary, :failed),
      retry_scope: retry_scope(context),
      retry_run_ids: retry_run_ids(context),
      retry_nonretryable_run_ids: retry_item_values(summary, :nonretryable_items, :run_id),
      retry_nonretryable_event_ids: retry_item_values(summary, :nonretryable_items, :event_id),
      retry_nonretryable_items: retry_items(summary, :nonretryable_items),
      retry_skipped_run_ids: retry_item_values(summary, :skipped_items, :run_id),
      retry_skipped_event_ids: retry_item_values(summary, :skipped_items, :event_id),
      retry_skipped_items: retry_items(summary, :skipped_items),
      retry_error_run_ids: retry_error_values(summary, :run_id),
      retry_error_event_ids: retry_error_values(summary, :event_id),
      retry_error_items: retry_error_items(summary),
      message: group_retry_flash(summary)
    )
    |> put_result_events(Map.get(summary, :events, []))
    |> put_action_context(context)
  end

  def action_outcome(:retry_group_failed_jobs, {:error, reason}, context) do
    outcome(
      action: :retry_group_failed_jobs,
      status: :error,
      kind: :error,
      reason: "retry_group_failed_jobs_failed",
      request_group_id: action_request_group_id(reason, context),
      error: reason,
      message:
        workflow_failure_message(
          "Failed to retry historical data workflow group jobs",
          reason
        )
    )
    |> put_action_context(context)
  end

  def action_attrs(nil), do: nil

  def action_attrs(outcome) when is_map(outcome) do
    %{
      action: text_value(Map.get(outcome, :action)),
      status: text_value(Map.get(outcome, :status)),
      kind: text_value(Map.get(outcome, :kind)),
      reason: text_value(Map.get(outcome, :reason)),
      stage: text_value(Map.get(outcome, :stage)),
      request_group_id: text_value(Map.get(outcome, :request_group_id)),
      job_id: text_value(Map.get(outcome, :job_id)),
      count: text_value(Map.get(outcome, :count)),
      retried: text_value(Map.get(outcome, :retried)),
      retry_nonretryable: text_value(Map.get(outcome, :retry_nonretryable)),
      retry_skipped: text_value(Map.get(outcome, :retry_skipped)),
      retry_errors: text_value(Map.get(outcome, :retry_errors)),
      retry_scope: text_value(Map.get(outcome, :retry_scope)),
      retry_run_ids: retry_run_ids(outcome),
      retry_nonretryable_run_ids: text_value(Map.get(outcome, :retry_nonretryable_run_ids)),
      retry_nonretryable_event_ids: text_value(Map.get(outcome, :retry_nonretryable_event_ids)),
      retry_nonretryable_items: text_value(Map.get(outcome, :retry_nonretryable_items)),
      retry_skipped_run_ids: text_value(Map.get(outcome, :retry_skipped_run_ids)),
      retry_skipped_event_ids: text_value(Map.get(outcome, :retry_skipped_event_ids)),
      retry_skipped_items: text_value(Map.get(outcome, :retry_skipped_items)),
      retry_error_run_ids: text_value(Map.get(outcome, :retry_error_run_ids)),
      retry_error_event_ids: text_value(Map.get(outcome, :retry_error_event_ids)),
      retry_error_items: text_value(Map.get(outcome, :retry_error_items)),
      queued_jobs: text_value(Map.get(outcome, :queued_jobs)),
      failed_jobs: text_value(Map.get(outcome, :failed_jobs)),
      result_event_ids: text_value(Map.get(outcome, :result_event_ids)),
      target_event_id: text_value(Map.get(outcome, :target_event_id)),
      target_run_id: text_value(Map.get(outcome, :target_run_id)),
      dashboard_context: non_empty_map(Map.get(outcome, :dashboard_context)),
      message: Map.get(outcome, :message)
    }
    |> Enum.reject(fn {_key, value} -> blank?(value) end)
    |> Map.new()
  end

  def request_flash([_event]), do: "Historical data workflow request recorded."

  def request_flash(events) do
    "Historical data workflow request group recorded for #{length(events)} points."
  end

  def workflow_flash(stage, {:ok, %{job_id: job_id}}) when is_binary(job_id) do
    {:info, "Historical data workflow #{stage} recorded and job #{job_id} queued."}
  end

  def workflow_flash(stage, {:ok, nil}) do
    {:info, "Historical data workflow #{stage} recorded."}
  end

  def workflow_flash(stage, {:error, reason}) do
    {:error,
     "Historical data workflow #{stage} recorded, but job dispatch failed: #{reason_text(reason)}"}
  end

  def group_flash("started", events, job_results) do
    queued_count =
      Enum.count(job_results, &match?({:ok, %{job_id: job_id}} when is_binary(job_id), &1))

    failed_count = group_dispatch_failed_count(job_results)

    if failed_count > 0 do
      {:error,
       "Historical data workflow group started for #{length(events)} items; #{queued_count} #{job_label(queued_count)} queued and #{failed_count} #{dispatch_label(failed_count)} failed."}
    else
      {:info,
       "Historical data workflow group started for #{length(events)} items; #{queued_count} #{job_label(queued_count)} queued."}
    end
  end

  def group_flash(stage, events, _job_results) do
    {:info, "Historical data workflow group #{stage} recorded for #{length(events)} items."}
  end

  def group_retry_flash(summary) do
    "Retried #{summary.retried} failed workflow jobs; skipped #{summary.nonretryable} non-retryable, #{summary.skipped} not-failed or missing, and #{summary.failed} retry errors."
  end

  defp group_retry_status(%{failed: failed}) when is_integer(failed) and failed > 0,
    do: :degraded

  defp group_retry_status(_summary), do: :ok

  defp group_retry_kind(%{failed: failed}) when is_integer(failed) and failed > 0, do: :error
  defp group_retry_kind(_summary), do: :info

  defp group_retry_reason(%{failed: failed}) when is_integer(failed) and failed > 0,
    do: "retry_group_failed_jobs_degraded"

  defp group_retry_reason(_summary), do: "retry_group_failed_jobs_recorded"

  defp retry_scope(context) when is_map(context) do
    if retry_run_ids(context), do: "replacement_jobs"
  end

  defp retry_scope(_context), do: nil

  defp retry_run_ids(context) when is_map(context) do
    context
    |> Map.get(:retry_run_ids)
    |> normalize_retry_run_ids()
    |> case do
      [] -> nil
      run_ids -> Enum.join(run_ids, ",")
    end
  end

  defp retry_run_ids(_context), do: nil

  defp retry_error_values(summary, key) do
    summary
    |> retry_error_item_list()
    |> Enum.map(&text_value(item_value(&1, key)))
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      values -> Enum.join(values, ",")
    end
  end

  defp retry_item_values(summary, bucket, key) do
    summary
    |> retry_item_list(bucket)
    |> Enum.map(&text_value(item_value(&1, key)))
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      values -> Enum.join(values, ",")
    end
  end

  defp retry_items(summary, bucket) do
    summary
    |> retry_item_list(bucket)
    |> Enum.map(&retry_item_text/1)
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> nil
      items -> Enum.join(items, "; ")
    end
  end

  defp retry_item_list(summary, bucket) when is_map(summary) and is_atom(bucket) do
    case Map.get(summary, bucket) || Map.get(summary, Atom.to_string(bucket)) do
      items when is_list(items) -> items
      _items -> []
    end
  end

  defp retry_item_list(_summary, _bucket), do: []

  defp retry_error_items(summary) do
    summary
    |> retry_error_item_list()
    |> Enum.map(&retry_item_text/1)
    |> Enum.reject(&blank?/1)
    |> case do
      [] -> nil
      items -> Enum.join(items, "; ")
    end
  end

  defp retry_error_item_list(summary) when is_map(summary) do
    case Map.get(summary, :retry_error_items) || Map.get(summary, "retry_error_items") do
      items when is_list(items) -> items
      _items -> []
    end
  end

  defp retry_error_item_list(_summary), do: []

  defp retry_item_text(item) when is_map(item) do
    [
      {"run", item_value(item, :run_id)},
      {"event", item_value(item, :event_id)},
      {"job", item_value(item, :job_id)},
      {"status", item_value(item, :job_status)},
      {"action", item_value(item, :recovery_action)},
      {"reason", item_value(item, :reason)}
    ]
    |> Enum.flat_map(fn {label, value} ->
      case text_value(value) do
        nil -> []
        "" -> []
        value -> ["#{label}=#{value}"]
      end
    end)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp retry_item_text(_item), do: nil

  defp item_value(item, key) when is_map(item) do
    Map.get(item, key) || Map.get(item, Atom.to_string(key))
  end

  defp normalize_retry_run_ids(run_ids) when is_list(run_ids) do
    run_ids
    |> Enum.flat_map(&normalize_retry_run_ids/1)
    |> Enum.uniq()
  end

  defp normalize_retry_run_ids(run_ids) when is_binary(run_ids) do
    run_ids
    |> String.split([",", ";", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_retry_run_ids(_run_ids), do: []

  defp non_empty_map(value) when is_map(value) and map_size(value) > 0, do: value
  defp non_empty_map(_value), do: nil

  def no_eligible_group_flash(request_group_id, stage) do
    "No #{group_stage_label(stage)} items are eligible in request group #{request_group_id}. The workflow panel was refreshed with current eligibility counts."
  end

  def request_form_defaults(context \\ default_request_context())

  def request_form_defaults(nil), do: request_form_defaults(default_request_context())

  def request_form_defaults(context) when is_map(context) do
    HistoricalWorkflowRequestDefaults.new(context)
  end

  def group_stage_label(stage) do
    case stage do
      "approved" -> "approve"
      "rejected" -> "reject"
      "started" -> "start"
      "completed" -> "complete"
      "failed" -> "fail"
      "requested" -> "request"
      other when is_binary(other) -> String.replace(other, "_", " ")
      _other -> "selected"
    end
  end

  defp outcome(attrs), do: HistoricalWorkflowActionOutcome.new(attrs)

  defp put_action_context(outcome, context) when is_map(context) do
    outcome
    |> put_first_present(:target_event_id, context, [:target_event_id, :event_id])
    |> put_first_present(:target_run_id, context, [:target_run_id, :run_id])
    |> put_first_present(:request_group_id, context, [:request_group_id])
    |> put_dashboard_context(context)
  end

  defp put_action_context(outcome, _context), do: outcome

  defp action_request_group_id(
         {:historical_workflow_group_retry_blocked, request_group_id, _reason},
         _context
       ) do
    request_group_id
  end

  defp action_request_group_id(_reason, context) when is_map(context),
    do: Map.get(context, :request_group_id)

  defp action_request_group_id(_reason, _context), do: nil

  defp put_result_events(outcome, events) when is_list(events) do
    event_ids = event_ids(events)

    outcome
    |> maybe_put(:result_event_ids, Enum.join(event_ids, ","))
    |> maybe_put(:target_event_id, List.first(event_ids))
  end

  defp put_result_events(outcome, _events), do: outcome

  defp event_ids(events) do
    events
    |> Enum.map(&event_id/1)
    |> Enum.reject(&blank?/1)
  end

  defp event_id(event) when is_map(event) do
    event
    |> Map.get(:backfill_lifecycle_event_id, Map.get(event, "backfill_lifecycle_event_id"))
    |> case do
      nil -> Map.get(event, :event_id, Map.get(event, "event_id"))
      event_id -> event_id
    end
    |> text_value()
  end

  defp event_id(_event), do: nil

  defp maybe_put(outcome, _key, nil), do: outcome
  defp maybe_put(outcome, _key, ""), do: outcome
  defp maybe_put(outcome, key, value), do: Map.put(outcome, key, value)

  defp job_id_from_result({:ok, %{job_id: job_id}}), do: text_value(job_id)
  defp job_id_from_result(_job_result), do: nil

  defp put_first_present(outcome, target_key, context, source_keys) do
    case Enum.find_value(source_keys, &present_context_value(context, &1)) do
      nil -> outcome
      value -> Map.put(outcome, target_key, value)
    end
  end

  defp present_context_value(context, key) do
    case Map.get(context, key) do
      value when is_binary(value) and value != "" -> value
      value when is_integer(value) -> Integer.to_string(value)
      _value -> nil
    end
  end

  defp put_dashboard_context(outcome, context) when is_map(context) do
    dashboard_context =
      %{
        dashboard_id: present_context_value(context, :dashboard_id),
        dashboard_version: present_context_value(context, :dashboard_version),
        dashboard_time_mode: present_context_value(context, :dashboard_time_mode),
        dashboard_replay_run_id: present_context_value(context, :dashboard_replay_run_id),
        dashboard_data_view: present_context_value(context, :dashboard_data_view),
        dashboard_limit_mode: present_context_value(context, :dashboard_limit_mode)
      }
      |> Enum.reject(fn {_key, value} -> blank?(value) end)
      |> Map.new()

    case dashboard_context do
      context when map_size(context) == 0 -> outcome
      context -> Map.put(outcome, :dashboard_context, context)
    end
  end

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp status_from_kind(:info), do: :ok
  defp status_from_kind(:error), do: :error

  defp stage_success_reason({:ok, %{job_id: job_id}}) when is_binary(job_id),
    do: "stage_recorded_job_queued"

  defp stage_success_reason({:ok, nil}), do: "stage_recorded"
  defp stage_success_reason({:error, _reason}), do: "stage_recorded_job_dispatch_failed"

  defp group_success_reason("started"), do: "group_started"
  defp group_success_reason(stage) when is_binary(stage), do: "group_#{stage}_recorded"
  defp group_success_reason(_stage), do: "group_stage_recorded"

  defp group_success_reason("started", job_results) do
    if group_dispatch_failed?(job_results) do
      "group_started_job_dispatch_degraded"
    else
      "group_started"
    end
  end

  defp group_success_reason(stage, _job_results), do: group_success_reason(stage)

  defp group_status("started", job_results, _kind) do
    if group_dispatch_failed?(job_results), do: :degraded, else: :ok
  end

  defp group_status(_stage, _job_results, kind), do: status_from_kind(kind)

  defp group_dispatch_failed?(job_results), do: group_dispatch_failed_count(job_results) > 0

  defp group_queued_job_count("started", job_results) when is_list(job_results) do
    Enum.count(job_results, &match?({:ok, %{job_id: job_id}} when is_binary(job_id), &1))
  end

  defp group_queued_job_count(_stage, _job_results), do: nil

  defp group_dispatch_failed_count("started", job_results),
    do: group_dispatch_failed_count(job_results)

  defp group_dispatch_failed_count(_stage, _job_results), do: nil

  defp group_dispatch_failed_count(job_results) when is_list(job_results) do
    Enum.count(job_results, &match?({:error, _reason}, &1))
  end

  defp group_dispatch_failed_count(_job_results), do: 0

  defp dispatch_label(1), do: "job dispatch"
  defp dispatch_label(_count), do: "job dispatches"

  defp job_label(1), do: "job"
  defp job_label(_count), do: "jobs"

  defp request_success_reason([_event]), do: "request_recorded"
  defp request_success_reason(_events), do: "request_group_recorded"

  defp workflow_failure_message(prefix, reason) do
    case workflow_error_message(reason) do
      nil -> "#{prefix}: #{reason_text(reason)}"
      message -> message
    end
  end

  defp workflow_error_message({:historical_workflow_stage_transition_blocked, event_id, reason}) do
    "Historical data workflow transition was blocked for event #{event_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message(
         {:historical_workflow_correction_transition_blocked, event_id, reason}
       ) do
    "Corrected historical data workflow transition was blocked for event #{event_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message({:historical_workflow_correction_source_superseded, event_id}) do
    "Correction source event #{event_id} has already been superseded by a completed correction."
  end

  defp workflow_error_message({:historical_workflow_correction_request_blocked, event_id, reason}) do
    "Corrected historical data workflow request was blocked for source event #{event_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message({:historical_workflow_retry_blocked, event_id, reason}) do
    "Historical data workflow retry was blocked for event #{event_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message(
         {:historical_workflow_group_retry_blocked, request_group_id, reason}
       ) do
    "Historical data workflow group retry was blocked for request group #{request_group_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message(
         {:historical_workflow_stale_replacement_inspection_blocked, event_id, reason}
       ) do
    "Stale replacement job action was blocked for event #{event_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message(
         {:historical_workflow_missing_replacement_inspection_blocked, run_id, reason}
       ) do
    "Missing replacement job inspection was blocked for run #{run_id}: #{reason_text(reason)}."
  end

  defp workflow_error_message({:invalid_historical_workflow_correction_source, event_id, reason}) do
    "Correction source event #{event_id} is not valid: #{reason_text(reason)}."
  end

  defp workflow_error_message({:invalid_historical_workflow_correction_event, event_id, reason}) do
    "Correction event #{event_id} is not valid: #{reason_text(reason)}."
  end

  defp workflow_error_message({:invalid_historical_workflow_transition_source, event_id, reason}) do
    "Historical data workflow transition source event #{event_id} is not valid: #{reason_text(reason)}."
  end

  defp workflow_error_message({:historical_workflow_correction_source_not_found, event_id}) do
    "Correction source event #{event_id} was not found."
  end

  defp workflow_error_message({:historical_workflow_event_not_found, event_id}) do
    "Historical workflow event #{event_id} was not found."
  end

  defp workflow_error_message({:request_group_not_found, request_group_id}) do
    "Historical workflow request group #{request_group_id} was not found."
  end

  defp workflow_error_message({:missing_field, field}) do
    "Missing required field #{reason_text(field)}."
  end

  defp workflow_error_message({:unexpected_job_type, job_type}) do
    "The selected job is #{reason_text(job_type)}, not a historical data workflow job."
  end

  defp workflow_error_message(_reason), do: nil

  defp reason_text("already_in_stage"), do: "the workflow is already in that stage"
  defp reason_text("stage_transition_out_of_order"), do: "the requested stage is out of order"
  defp reason_text("job_status_missing"), do: "workflow job status is missing"
  defp reason_text("job_not_failed"), do: "the workflow job is not failed"
  defp reason_text("request_group_missing"), do: "request group is missing"
  defp reason_text("no_retryable_group_failures"), do: "the group has no retryable failed jobs"

  defp reason_text("correct_workflow_request"),
    do: "this failure must be corrected before it can continue"

  defp reason_text("correction_not_required"),
    do: "the selected failure does not require correction"

  defp reason_text("retry_blocked"), do: "the failure is not retryable"

  defp reason_text(:correct_workflow_request),
    do: "this failure must be corrected before it can continue"

  defp reason_text(:correction_not_required),
    do: "the selected failure does not require correction"

  defp reason_text(:nonretryable_failure), do: "the failure is not retryable"

  defp reason_text(:job_run_mismatch),
    do: "the selected job does not belong to the selected event run"

  defp reason_text(:job_id_mismatch), do: "the failed event references a different workflow job"
  defp reason_text(:job_not_stale), do: "the selected replacement job is not stale"
  defp reason_text(:workflow_mismatch), do: "the source event belongs to a different workflow"
  defp reason_text(:not_failed), do: "the source event is not a failed workflow event"

  defp reason_text(:missing_source_event),
    do: "the correction event does not reference a failed source event"

  defp reason_text(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> reason_text()

  defp reason_text(reason) when is_binary(reason), do: String.replace(reason, "_", " ")

  defp reason_text(reason), do: inspect(reason)

  defp default_request_context do
    %{
      realm: "backfill",
      data_source_id: "",
      source_binding_id: "",
      point_id: "",
      source_from: "",
      source_to: "",
      dashboard_id: "",
      dashboard_version: "",
      dashboard_time_mode: "",
      dashboard_replay_run_id: "",
      dashboard_data_view: "",
      dashboard_limit_mode: ""
    }
  end
end
