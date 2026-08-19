defmodule Cadence.Telemetry.DataManagement.WorkflowJobs do
  @moduledoc """
  Enqueueing and execution for historical telemetry workflow jobs.

  This boundary owns job payloads, historical source reads, sample persistence,
  and the completion or failure lifecycle events emitted by a job run.
  """

  alias Cadence.Jobs
  alias Cadence.Telemetry.DataManagement.HistoricalSourceSamples
  alias Cadence.Telemetry.DataManagement.WorkflowEvents
  alias Cadence.Telemetry.Storage

  @spec start(atom() | binary(), map()) :: {:ok, Jobs.Job.t()} | {:error, term()}
  def start(workflow, attrs)
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         :ok <- WorkflowEvents.validate_context(workflow, attrs) do
      run_id = workflow_run_id(workflow, attrs)

      Jobs.enqueue(
        :telemetry_historical_data_workflow,
        get_attr(attrs, :mission_id),
        run_id,
        job_payload(workflow, attrs)
      )
    end
  end

  @spec execute(binary(), Cadence.Telemetry.DataManagement.persistence_policy()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def execute(workflow_run_id, %{} = policy) when is_binary(workflow_run_id) do
    with {:ok, %Jobs.Job{} = job} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, workflow_run_id),
         {:ok, workflow, attrs} <- job_attrs(job.payload) do
      case execute_job(policy, job, workflow, attrs) do
        {:ok, event} ->
          {:ok, event}

        {:error, reason} ->
          _result = record_failure(job, workflow, attrs, reason)
          {:error, reason}
      end
    end
  end

  defp job_payload(workflow, attrs) do
    %{
      "workflow" => Atom.to_string(workflow),
      "attrs" => attrs
    }
  end

  defp job_attrs(%{"workflow" => workflow, "attrs" => attrs})
       when is_binary(workflow) and is_map(attrs) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow) do
      {:ok, workflow, attrs}
    end
  end

  defp job_attrs(payload),
    do: {:error, {:invalid_historical_data_workflow_job_payload, payload}}

  defp execute_job(policy, %Jobs.Job{} = job, workflow, attrs) do
    with {:ok, samples, diagnostics} <-
           HistoricalSourceSamples.fetch(attrs, policy.history_store),
         :ok <- persist_samples(policy.storage, workflow, samples, attrs) do
      attrs =
        attrs
        |> put_attr("sample_count", length(samples))
        |> put_attr("reason", "historical_data_job_completed")
        |> put_attr(
          "payload",
          lifecycle_payload(job, "completed", diagnostics, attrs)
        )

      WorkflowEvents.record(workflow, :completed, attrs, dashboard_runtime_invalidation?: true)
    end
  end

  defp persist_samples(_storage_policy, _workflow, [], _attrs), do: :ok

  defp persist_samples(storage_policy, workflow, samples, attrs) do
    with {:ok, write_opts} <- write_opts(workflow, attrs) do
      Storage.persist_samples(storage_policy, samples, write_opts)
    end
  end

  defp write_opts(workflow, attrs) do
    [
      organization_id: get_attr(attrs, :organization_id),
      realm: get_attr(attrs, :realm),
      data_source_id: get_attr(attrs, :data_source_id),
      binding_id: get_attr(attrs, :binding_id),
      source_endpoint_id: get_attr(attrs, :source_endpoint_id),
      replay_run_id: get_attr(attrs, :replay_run_id),
      recorded_at: get_attr(attrs, :recorded_at),
      metadata: get_attr(attrs, :metadata, %{}),
      validity_state: get_attr(attrs, :validity_state),
      revision: get_attr(attrs, :revision),
      supersedes_observation_id: get_attr(attrs, :supersedes_observation_id),
      record_current_values?: get_attr(attrs, :record_current_values?),
      dashboard_runtime_invalidation?: true,
      dashboard_runtime_cache: get_attr(attrs, :dashboard_runtime_cache),
      record_backfill_lifecycle_event?: false,
      backfill_lifecycle_event_type: completion_event_type(workflow),
      backfill_run_id: workflow_run_id(workflow, attrs),
      import_run_id: get_attr(attrs, :import_run_id),
      authority: get_attr(attrs, :authority),
      reason: "historical_data_job_write",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> then(&{:ok, &1})
  end

  defp completion_event_type(:backfill), do: :backfill_completed
  defp completion_event_type(:import), do: :import_completed

  defp record_failure(%Jobs.Job{} = job, workflow, attrs, reason) do
    attrs =
      attrs
      |> put_attr("reason", "historical_data_job_failed")
      |> put_attr(
        "payload",
        lifecycle_payload(
          job,
          "failed",
          source_failure_diagnostics(attrs, reason),
          attrs
        )
      )

    WorkflowEvents.record(workflow, :failed, attrs, dashboard_runtime_invalidation?: true)
  end

  defp lifecycle_payload(%Jobs.Job{} = job, status, diagnostics, attrs) do
    attrs
    |> job_context_payload()
    |> Map.merge(%{
      "job_id" => job.job_id,
      "job_type" => Atom.to_string(job.job_type),
      "workflow_job_status" => status,
      "source" => diagnostics
    })
  end

  defp job_context_payload(attrs) do
    attrs
    |> get_attr(:payload, %{})
    |> ensure_map()
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
  end

  defp source_failure_diagnostics(attrs, reason) do
    %{
      "point_id" => get_attr(attrs, :point_id) || get_attr(attrs, :observable_id),
      "source_window" =>
        HistoricalSourceSamples.window_diagnostics(
          from_observed_at: get_attr(attrs, :source_from),
          to_observed_at: get_attr(attrs, :source_to),
          from_receipt_time: get_attr(attrs, :receipt_from),
          to_receipt_time: get_attr(attrs, :receipt_to)
        ),
      "source_identity" => HistoricalSourceSamples.identity_diagnostics(attrs),
      "source_limit" => get_attr(attrs, :source_limit) || get_attr(attrs, :limit),
      "failure" => failure_diagnostics(reason)
    }
  end

  defp failure_diagnostics(reason) do
    %{
      "code" => failure_code(reason),
      "detail" => inspect(reason),
      "retryable" => failure_retryable?(reason),
      "retry_blockers" => failure_retry_blockers(reason),
      "recovery_action" => failure_recovery_action(reason)
    }
  end

  defp failure_code({:missing_field, field}), do: "missing_field:#{diagnostic_value_text(field)}"

  defp failure_code({:invalid_datetime_field, field, _value, _reason}),
    do: "invalid_datetime_field:#{diagnostic_value_text(field)}"

  defp failure_code({:invalid_datetime_field, field, _value}),
    do: "invalid_datetime_field:#{diagnostic_value_text(field)}"

  defp failure_code({:invalid_historical_data_workflow_job_payload, _payload}),
    do: "invalid_job_payload"

  defp failure_code({:error, reason}), do: "error:#{diagnostic_value_text(reason)}"
  defp failure_code({:exit, reason}), do: "exit:#{diagnostic_value_text(reason)}"
  defp failure_code({:throw, reason}), do: "throw:#{diagnostic_value_text(reason)}"
  defp failure_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_code(_reason), do: "workflow_execution_failed"

  defp failure_retryable?({:missing_field, _field}), do: false
  defp failure_retryable?({:invalid_datetime_field, _field, _value, _reason}), do: false
  defp failure_retryable?({:invalid_datetime_field, _field, _value}), do: false
  defp failure_retryable?({:invalid_historical_data_workflow_job_payload, _payload}), do: false
  defp failure_retryable?(_reason), do: true

  defp failure_retry_blockers(reason) do
    case reason do
      {:missing_field, field} ->
        ["missing #{diagnostic_value_text(field)}"]

      {:invalid_datetime_field, field, _value, _reason} ->
        ["invalid #{diagnostic_value_text(field)}"]

      {:invalid_datetime_field, field, _value} ->
        ["invalid #{diagnostic_value_text(field)}"]

      {:invalid_historical_data_workflow_job_payload, _payload} ->
        ["invalid job payload"]

      _reason ->
        []
    end
  end

  defp failure_recovery_action(reason) do
    if failure_retryable?(reason), do: "retry_job", else: "correct_workflow_request"
  end

  defp workflow_run_id(:backfill, attrs), do: get_attr(attrs, :backfill_run_id)

  defp workflow_run_id(:import, attrs),
    do: get_attr(attrs, :import_run_id) || get_attr(attrs, :backfill_run_id)

  defp diagnostic_value_text(nil), do: nil
  defp diagnostic_value_text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp diagnostic_value_text(value) when is_binary(value), do: value
  defp diagnostic_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp diagnostic_value_text(value) when is_integer(value), do: Integer.to_string(value)
  defp diagnostic_value_text(value), do: inspect(value)

  defp put_attr(attrs, key, value) when is_binary(key), do: Map.put(attrs, key, value)

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
