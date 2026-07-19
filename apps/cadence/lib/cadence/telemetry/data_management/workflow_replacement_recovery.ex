defmodule Cadence.Telemetry.DataManagement.WorkflowReplacementRecovery do
  @moduledoc """
  Inspection and recovery of missing or stale historical-workflow replacement jobs.

  This boundary validates replacement lifecycle evidence, records advisory
  inspection events, and requeues stale running jobs with authoritative audit
  evidence.
  """

  alias Cadence.Jobs
  alias Cadence.Telemetry.DataManagement.WorkflowEventEvidence
  alias Cadence.Telemetry.Storage

  @stale_job_seconds 15 * 60

  @spec record_missing_inspection(binary(), binary(), map(), keyword()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_missing_inspection(request_group_id, replacement_run_id, attrs, opts \\ [])

  def record_missing_inspection(request_group_id, replacement_run_id, attrs, opts)
      when is_binary(request_group_id) and is_binary(replacement_run_id) and is_map(attrs) and
             is_list(opts) do
    with {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id),
         {:ok, source_event} <-
           missing_replacement_event(
             mission_id,
             organization_id,
             request_group_id,
             replacement_run_id
           ),
         :ok <- require_missing_replacement_policy(source_event) do
      record_missing_inspection_event(source_event, attrs, opts)
    end
  end

  def record_missing_inspection(_request_group_id, _replacement_run_id, _attrs, _opts),
    do: {:error, {:missing_field, :request_group_id}}

  @spec record_stale_inspection(binary(), binary(), map(), keyword()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_stale_inspection(job_id, event_id, attrs, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    event_opts =
      attrs
      |> Map.take([:organization_id, :mission_id])
      |> Keyword.new()

    with %Storage.BackfillLifecycleEvent{} = source_event <-
           Storage.fetch_backfill_lifecycle_event(event_id, event_opts),
         :ok <- require_replacement_event(source_event),
         {:ok, job} <- require_stale_job(job_id, source_event),
         :ok <- require_stale_policy(source_event, job),
         {:ok, inspection_event} <-
           record_stale_inspection_event(source_event, job, attrs, opts) do
      {:ok, inspection_event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec requeue_stale_job(binary(), binary(), map(), keyword()) ::
          {:ok, Jobs.Job.t(), Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def requeue_stale_job(job_id, event_id, attrs, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    event_opts =
      attrs
      |> Map.take([:organization_id, :mission_id])
      |> Keyword.new()

    with %Storage.BackfillLifecycleEvent{} = source_event <-
           Storage.fetch_backfill_lifecycle_event(event_id, event_opts),
         :ok <- require_replacement_event(source_event),
         {:ok, job} <- require_stale_job(job_id, source_event),
         :ok <- require_stale_policy(source_event, job),
         {:ok, requeued_job} <-
           Jobs.requeue_running_job(job.job_id, :dashboard_stale_replacement_requeued),
         {:ok, requeue_event} <-
           record_stale_requeue_event(source_event, job, requeued_job, attrs, opts) do
      {:ok, requeued_job, requeue_event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp missing_replacement_event(
         mission_id,
         organization_id,
         request_group_id,
         replacement_run_id
       ) do
    mission_id
    |> Storage.list_backfill_lifecycle_events(
      organization_id: organization_id,
      backfill_run_id: replacement_run_id,
      limit: 1_000
    )
    |> Enum.filter(fn event ->
      WorkflowEventEvidence.correction?(event) and
        Storage.BackfillLifecycleGroup.payload_value(event, :request_group_id) ==
          request_group_id
    end)
    |> Enum.sort_by(fn event ->
      {event.occurred_at || DateTime.from_unix!(0), event.backfill_lifecycle_event_id}
    end)
    |> List.last()
    |> case do
      %Storage.BackfillLifecycleEvent{} = event ->
        {:ok, event}

      nil ->
        {:error,
         {:historical_workflow_missing_replacement_inspection_blocked, replacement_run_id,
          :replacement_event_not_found}}
    end
  end

  defp require_missing_replacement_policy(source_event) do
    case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, source_event.backfill_run_id) do
      {:error, :job_not_found} ->
        :ok

      {:ok, %Jobs.Job{} = job} ->
        {:error,
         {:historical_workflow_missing_replacement_inspection_blocked,
          source_event.backfill_run_id, {:job_exists, job.status}}}
    end
  end

  defp require_replacement_event(source_event) do
    if WorkflowEventEvidence.correction?(source_event) do
      :ok
    else
      {:error,
       {:historical_workflow_stale_replacement_inspection_blocked,
        source_event.backfill_lifecycle_event_id, :not_replacement_event}}
    end
  end

  defp require_stale_job(job_id, source_event) do
    with {:ok, %Jobs.Job{} = job} <- Jobs.fetch_job(job_id) do
      cond do
        job.job_type != :telemetry_historical_data_workflow ->
          {:error, {:unexpected_job_type, job.job_type}}

        job.run_id != source_event.backfill_run_id ->
          {:error,
           {:historical_workflow_stale_replacement_inspection_blocked,
            source_event.backfill_lifecycle_event_id, :job_run_mismatch}}

        true ->
          {:ok, job}
      end
    end
  end

  defp require_stale_policy(source_event, %Jobs.Job{} = job) do
    cond do
      job.status != :running ->
        {:error,
         {:historical_workflow_stale_replacement_inspection_blocked,
          source_event.backfill_lifecycle_event_id, :job_not_running}}

      not stale_job?(job) ->
        {:error,
         {:historical_workflow_stale_replacement_inspection_blocked,
          source_event.backfill_lifecycle_event_id, :job_not_stale}}

      true ->
        :ok
    end
  end

  defp stale_job?(%Jobs.Job{started_at: %DateTime{} = started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second) >= @stale_job_seconds
  end

  defp stale_job?(_job), do: false

  defp record_stale_inspection_event(source_event, job, attrs, opts) do
    source_event
    |> stale_inspection_attrs(job, attrs)
    |> Storage.record_backfill_lifecycle_event(event_opts(opts))
  end

  defp record_missing_inspection_event(source_event, attrs, opts) do
    source_event
    |> missing_inspection_attrs(attrs)
    |> Storage.record_backfill_lifecycle_event(event_opts(opts))
  end

  defp record_stale_requeue_event(source_event, job, requeued_job, attrs, opts) do
    source_event
    |> stale_requeue_attrs(job, requeued_job, attrs)
    |> Storage.record_backfill_lifecycle_event(event_opts(opts))
  end

  defp stale_inspection_attrs(source_event, job, attrs) do
    %{
      backfill_run_id: source_event.backfill_run_id,
      import_run_id: source_event.backfill_run_id,
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      realm: source_event.realm,
      replay_run_id: source_event.replay_run_id,
      data_source_id: source_event.data_source_id,
      binding_id: source_event.binding_id,
      observable_id: source_event.observable_id,
      point_id: source_event.point_id,
      source_from: source_event.source_from,
      source_to: source_event.source_to,
      receipt_from: source_event.receipt_from,
      receipt_to: source_event.receipt_to,
      event_type: stale_inspection_event_type(source_event),
      authority: :advisory,
      reason: "dashboard_historical_workflow_stale_replacement_inspected",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload: stale_payload(source_event, job, "inspect_stale_replacement_job")
    }
    |> compact_attrs()
  end

  defp missing_inspection_attrs(source_event, attrs) do
    %{
      backfill_run_id: source_event.backfill_run_id,
      import_run_id: source_event.backfill_run_id,
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      realm: source_event.realm,
      replay_run_id: source_event.replay_run_id,
      data_source_id: source_event.data_source_id,
      binding_id: source_event.binding_id,
      observable_id: source_event.observable_id,
      point_id: source_event.point_id,
      source_from: source_event.source_from,
      source_to: source_event.source_to,
      receipt_from: source_event.receipt_from,
      receipt_to: source_event.receipt_to,
      event_type: missing_inspection_event_type(source_event),
      authority: :advisory,
      reason: "dashboard_historical_workflow_missing_replacement_inspected",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload: missing_payload(source_event, "inspect_missing_replacement_job")
    }
    |> compact_attrs()
  end

  defp stale_requeue_attrs(source_event, job, requeued_job, attrs) do
    %{
      backfill_run_id: source_event.backfill_run_id,
      import_run_id: source_event.backfill_run_id,
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      realm: source_event.realm,
      replay_run_id: source_event.replay_run_id,
      data_source_id: source_event.data_source_id,
      binding_id: source_event.binding_id,
      observable_id: source_event.observable_id,
      point_id: source_event.point_id,
      source_from: source_event.source_from,
      source_to: source_event.source_to,
      receipt_from: source_event.receipt_from,
      receipt_to: source_event.receipt_to,
      event_type: stale_requeue_event_type(source_event),
      authority: :authoritative,
      reason: "dashboard_historical_workflow_stale_replacement_requeued",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload:
        source_event
        |> stale_payload(job, "requeue_stale_replacement_job")
        |> Map.merge(%{
          "stale_replacement_requeued_job_id" => requeued_job.job_id,
          "stale_replacement_requeued_job_status" => Atom.to_string(requeued_job.status),
          "stale_replacement_requeued_job_attempt_count" => requeued_job.attempt_count,
          "stale_replacement_requeued_failure_reason" =>
            job_failure_reason_payload(requeued_job.failure_reason)
        })
    }
    |> compact_attrs()
  end

  defp stale_inspection_event_type(source_event) do
    case WorkflowEventEvidence.workflow(source_event) do
      :import -> :import_stale_replacement_inspected
      "import" -> :import_stale_replacement_inspected
      _workflow -> :backfill_stale_replacement_inspected
    end
  end

  defp missing_inspection_event_type(source_event) do
    case WorkflowEventEvidence.workflow(source_event) do
      :import -> :import_missing_replacement_inspected
      "import" -> :import_missing_replacement_inspected
      _workflow -> :backfill_missing_replacement_inspected
    end
  end

  defp stale_requeue_event_type(source_event) do
    case WorkflowEventEvidence.workflow(source_event) do
      :import -> :import_stale_replacement_requeued
      "import" -> :import_stale_replacement_requeued
      _workflow -> :backfill_stale_replacement_requeued
    end
  end

  defp stale_payload(source_event, job, action) do
    source_event.payload
    |> Map.take(workflow_context_keys())
    |> Map.merge(%{
      "stale_replacement_action" => action,
      "stale_replacement_source_event_id" => source_event.backfill_lifecycle_event_id,
      "stale_replacement_source_event_type" => Atom.to_string(source_event.event_type),
      "stale_replacement_run_id" => source_event.backfill_run_id,
      "stale_replacement_job_id" => job.job_id,
      "stale_replacement_job_status" => Atom.to_string(job.status),
      "stale_replacement_job_started_at" => datetime_payload(job.started_at),
      "stale_replacement_job_age_seconds" => job_age_seconds(job),
      "stale_replacement_stale_after_seconds" => @stale_job_seconds
    })
    |> compact_attrs()
  end

  defp missing_payload(source_event, action) do
    source_event.payload
    |> Map.take(workflow_context_keys())
    |> Map.merge(%{
      "missing_replacement_action" => action,
      "missing_replacement_source_event_id" => source_event.backfill_lifecycle_event_id,
      "missing_replacement_source_event_type" => Atom.to_string(source_event.event_type),
      "missing_replacement_run_id" => source_event.backfill_run_id,
      "missing_replacement_expected_job_type" => "telemetry_historical_data_workflow"
    })
    |> compact_attrs()
  end

  defp workflow_context_keys do
    [
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
    ]
  end

  defp event_opts(opts) do
    Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
  end

  defp job_failure_reason_payload(nil), do: nil
  defp job_failure_reason_payload(%{"reason" => reason}), do: job_failure_reason_payload(reason)
  defp job_failure_reason_payload(%{reason: reason}), do: job_failure_reason_payload(reason)
  defp job_failure_reason_payload(reason) when is_binary(reason), do: reason
  defp job_failure_reason_payload(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp job_failure_reason_payload(reason), do: inspect(reason)

  defp datetime_payload(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp datetime_payload(_value), do: nil

  defp job_age_seconds(%Jobs.Job{started_at: %DateTime{} = started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end

  defp job_age_seconds(_job), do: nil

  defp required_attr(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp get_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end
end
