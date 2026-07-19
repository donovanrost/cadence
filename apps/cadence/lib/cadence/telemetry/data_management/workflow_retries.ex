defmodule Cadence.Telemetry.DataManagement.WorkflowRetries do
  @moduledoc """
  Single-job and failed-group retry workflows for historical telemetry jobs.

  This boundary owns retry eligibility, group filtering, job retry execution,
  lifecycle audit events, and operator-facing retry summaries.
  """

  alias Cadence.Jobs
  alias Cadence.Telemetry.DataManagement.WorkflowEventEvidence
  alias Cadence.Telemetry.DataManagement.WorkflowEvents
  alias Cadence.Telemetry.DataManagement.WorkflowPolicy
  alias Cadence.Telemetry.Storage

  @spec retry_job(binary(), binary(), map(), keyword()) ::
          {:ok, Jobs.Job.t(), Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def retry_job(job_id, event_id, attrs, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    event_opts =
      attrs
      |> Map.take([:organization_id, :mission_id])
      |> Keyword.new()

    with %Storage.BackfillLifecycleEvent{} = source_event <-
           Storage.fetch_backfill_lifecycle_event(event_id, event_opts),
         :ok <- require_event_retryable(source_event),
         {:ok, source_job} <- require_retry_job(job_id, source_event),
         :ok <- require_retry_policy(source_event, source_job),
         {:ok, retried_job} <- retry_failed_job(job_id),
         {:ok, retry_event} <- record_retry_event(source_event, retried_job, attrs, opts) do
      {:ok, retried_job, retry_event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec retry_group(binary(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def retry_group(request_group_id, attrs, opts \\ [])

  def retry_group(request_group_id, attrs, opts)
      when is_binary(request_group_id) and is_map(attrs) and is_list(opts) do
    with {:ok, request_group_id} <- normalize_request_group_id(request_group_id),
         {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id),
         {:ok, failed_events} <-
           group_retry_events(mission_id, organization_id, request_group_id, opts) do
      failed_events
      |> Enum.reduce(group_retry_summary(), fn event, summary ->
        retry_group_failed_event(event, summary, attrs, opts)
      end)
      |> then(&{:ok, &1})
    end
  end

  def retry_group(_request_group_id, _attrs, _opts),
    do: {:error, {:missing_field, :request_group_id}}

  defp group_failed_events(mission_id, organization_id, request_group_id) do
    mission_id
    |> Storage.list_backfill_lifecycle_events(
      organization_id: organization_id,
      limit: 1_000
    )
    |> Enum.filter(fn event ->
      event.event_type in [:backfill_failed, :import_failed] and
        Storage.BackfillLifecycleGroup.payload_value(event, :request_group_id) == request_group_id
    end)
    |> Enum.sort_by(fn event ->
      {Storage.BackfillLifecycleGroup.payload_value(event, :request_item_index) || 0,
       event.backfill_run_id}
    end)
  end

  defp group_retry_events(mission_id, organization_id, request_group_id, opts) do
    failed_events =
      mission_id
      |> group_failed_events(organization_id, request_group_id)
      |> filter_group_retry_events(opts)

    with :ok <- require_group_retry_policy(request_group_id, failed_events) do
      {:ok, failed_events}
    end
  end

  defp filter_group_retry_events(failed_events, opts) do
    case retry_run_id_set(opts) do
      nil -> failed_events
      run_id_set -> Enum.filter(failed_events, &MapSet.member?(run_id_set, &1.backfill_run_id))
    end
  end

  defp retry_run_id_set(opts) do
    opts
    |> Keyword.get(:retry_run_ids)
    |> normalize_retry_run_ids()
    |> case do
      [] -> nil
      run_ids -> MapSet.new(run_ids)
    end
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

  defp require_retry_job(job_id, source_event) do
    with {:ok, %Jobs.Job{} = job} <- Jobs.fetch_job(job_id) do
      cond do
        job.job_type != :telemetry_historical_data_workflow ->
          {:error, {:unexpected_job_type, job.job_type}}

        job.run_id != source_event.backfill_run_id ->
          {:error,
           {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
            :job_run_mismatch}}

        true ->
          {:ok, job}
      end
    end
  end

  defp require_retry_policy(source_event, %Jobs.Job{} = job) do
    decision =
      source_event
      |> retry_policy_context(job)
      |> WorkflowPolicy.retry_job_action_policy()

    if decision.eligible? do
      :ok
    else
      {:error,
       {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
        decision.reason}}
    end
  end

  defp retry_policy_context(source_event, %Jobs.Job{} = job) do
    %{
      event_id: source_event.backfill_lifecycle_event_id,
      job_id: job.job_id,
      job_status: Atom.to_string(job.status),
      retryable: if(WorkflowEventEvidence.retryable?(source_event), do: "true", else: "false"),
      recovery_action: WorkflowEventEvidence.recovery_action(source_event)
    }
  end

  defp require_group_retry_policy(request_group_id, failed_events) do
    decision =
      %{
        request_group_id: request_group_id,
        request_group_retryable_failed:
          failed_events
          |> Enum.count(&group_retry_candidate?/1)
          |> Integer.to_string()
      }
      |> WorkflowPolicy.retry_group_action_policy()

    if decision.eligible? do
      :ok
    else
      {:error, {:historical_workflow_group_retry_blocked, request_group_id, decision.reason}}
    end
  end

  defp group_retry_candidate?(event) do
    WorkflowEventEvidence.retryable?(event) and not correction_request_blocked?(event)
  end

  defp retry_group_failed_event(event, summary, attrs, opts) do
    cond do
      not WorkflowEventEvidence.retryable?(event) or correction_request_blocked?(event) ->
        summary
        |> increment_summary(:nonretryable)
        |> prepend_nonretryable_item(event, nonretryable_group_retry_reason(event))

      not is_binary(event.backfill_run_id) or event.backfill_run_id == "" ->
        summary
        |> increment_summary(:skipped)
        |> prepend_skipped_item(event, nil, :missing_run_id)

      true ->
        retry_group_failed_job(event, summary, attrs, opts)
    end
  end

  defp retry_group_failed_job(event, summary, attrs, opts) do
    case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, event.backfill_run_id) do
      {:ok, %{status: :failed, job_id: job_id}} ->
        with {:ok, retried_job} <- retry_failed_job(job_id),
             {:ok, retry_event} <- record_retry_event(event, retried_job, attrs, opts) do
          summary
          |> increment_summary(:retried)
          |> prepend_retry_event(retry_event)
        else
          {:error, reason} ->
            summary
            |> increment_summary(:failed)
            |> prepend_retry_error_item(event, job_id, reason)
        end

      {:ok, job} ->
        summary
        |> increment_summary(:skipped)
        |> prepend_skipped_item(event, job, :job_not_failed)

      {:error, _reason} ->
        summary
        |> increment_summary(:skipped)
        |> prepend_skipped_item(event, nil, :job_status_missing)
    end
  end

  defp retry_failed_job(job_id) do
    with {:ok, %{job_type: :telemetry_historical_data_workflow}} <- Jobs.fetch_job(job_id),
         {:ok, retried_job} <- Jobs.retry_failed_job(job_id) do
      {:ok, retried_job}
    else
      {:ok, %{job_type: job_type}} -> {:error, {:unexpected_job_type, job_type}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_retry_event(source_event, retried_job, attrs, opts) do
    source_event
    |> retry_attrs(retried_job, attrs)
    |> then(
      &WorkflowEvents.record(
        WorkflowEventEvidence.workflow(source_event),
        :retried,
        &1,
        opts
      )
    )
  end

  defp retry_attrs(source_event, retried_job, attrs) do
    %{
      backfill_run_id: source_event.backfill_run_id,
      import_run_id: source_event.backfill_run_id,
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      realm: source_event.realm,
      data_source_id: source_event.data_source_id,
      binding_id: source_event.binding_id,
      observable_id: source_event.observable_id,
      point_id: source_event.point_id,
      source_from: source_event.source_from,
      source_to: source_event.source_to,
      receipt_from: source_event.receipt_from,
      receipt_to: source_event.receipt_to,
      authority: :authoritative,
      reason: "dashboard_historical_workflow_retried",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload: retry_payload(source_event, retried_job)
    }
    |> compact_attrs()
  end

  defp retry_payload(source_event, retried_job) do
    source_event.payload
    |> Map.take([
      "request_source",
      "request_mode",
      "request_group_id",
      "request_item_index",
      "request_item_count",
      "request_item_run_id",
      "correction_source",
      "correction_source_event_type",
      "recovery_action",
      "corrects_run_id",
      "corrects_event_id",
      "corrects_job_id",
      "dashboard_context",
      "comparison_review_origin"
    ])
    |> Map.merge(%{
      "retry_action" => "retry_job",
      "retry_source_event_id" => source_event.backfill_lifecycle_event_id,
      "retry_source_event_type" => Atom.to_string(source_event.event_type),
      "retry_job_id" => retried_job.job_id,
      "retry_job_status" => Atom.to_string(retried_job.status)
    })
  end

  defp require_event_retryable(source_event) do
    cond do
      correction_request_blocked?(source_event) ->
        {:error,
         {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
          :correct_workflow_request}}

      WorkflowEventEvidence.retryable?(source_event) ->
        :ok

      true ->
        {:error,
         {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
          :nonretryable_failure}}
    end
  end

  defp correction_request_blocked?(event) do
    WorkflowEventEvidence.recovery_action(event) == "correct_workflow_request" and
      not WorkflowEventEvidence.correction?(event)
  end

  defp group_retry_summary do
    %{
      retried: 0,
      nonretryable: 0,
      skipped: 0,
      failed: 0,
      nonretryable_items: [],
      skipped_items: [],
      retry_error_items: [],
      events: []
    }
  end

  defp increment_summary(summary, key), do: Map.update!(summary, key, &(&1 + 1))

  defp prepend_retry_error_item(summary, event, job_id, reason) do
    item = %{
      run_id: event.backfill_run_id,
      event_id: event.backfill_lifecycle_event_id,
      job_id: job_id,
      reason: retry_error_reason(reason)
    }

    Map.update(summary, :retry_error_items, [item], &[item | &1])
  end

  defp prepend_nonretryable_item(summary, event, reason) do
    item =
      event
      |> group_retry_item(nil, reason)
      |> Map.put(:recovery_action, WorkflowEventEvidence.recovery_action(event))
      |> compact_attrs()

    Map.update(summary, :nonretryable_items, [item], &[item | &1])
  end

  defp prepend_skipped_item(summary, event, job, reason) do
    item = group_retry_item(event, job, reason)
    Map.update(summary, :skipped_items, [item], &[item | &1])
  end

  defp group_retry_item(event, job, reason) do
    %{
      run_id: event.backfill_run_id,
      event_id: event.backfill_lifecycle_event_id,
      job_id: job && job.job_id,
      job_status: job && retry_error_reason(job.status),
      reason: retry_error_reason(reason)
    }
    |> compact_attrs()
  end

  defp nonretryable_group_retry_reason(event) do
    if correction_request_blocked?(event), do: :correction_required, else: :nonretryable_failure
  end

  defp retry_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp retry_error_reason(reason) when is_binary(reason), do: reason
  defp retry_error_reason(reason), do: inspect(reason)

  defp prepend_retry_event(summary, event) do
    %{summary | events: [event | Map.get(summary, :events, [])]}
  end

  defp normalize_request_group_id(request_group_id) do
    request_group_id = String.trim(request_group_id)

    if request_group_id == "" do
      {:error, {:missing_field, :request_group_id}}
    else
      {:ok, request_group_id}
    end
  end

  defp required_attr(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp get_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end
end
