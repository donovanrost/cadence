defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowCommands do
  @moduledoc false

  alias Cadence.Control.TelemetryDataManagement, as: DataManagement

  alias CadenceWeb.OpsDataOperationsLive.{
    HistoricalWorkflowCorrectionRequestHandoff,
    HistoricalWorkflowGroupStageHandoff,
    HistoricalWorkflowHandoff,
    HistoricalWorkflowJobRecoveryHandoff,
    HistoricalWorkflowParams,
    HistoricalWorkflowRequestHandoff,
    HistoricalWorkflowRetryGroupFailedJobsHandoff,
    HistoricalWorkflowStageHandoff
  }

  alias Cadence.Telemetry.Storage

  def record_stage(params, scope, mission, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %HistoricalWorkflowStageHandoff{} = handoff} <-
           HistoricalWorkflowHandoff.stage(params, scope, mission),
         {:ok, event} <- record_stage_event(handoff, opts) do
      {:ok, event, maybe_start_job(handoff.stage, handoff.workflow, handoff.attrs, opts)}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_stage_event(
         %HistoricalWorkflowStageHandoff{
           event_id: event_id,
           correction_source_event_id: source_event_id
         } = handoff,
         opts
       )
       when is_binary(event_id) and is_binary(source_event_id) do
    DataManagement.record_historical_data_workflow_stage_transition(
      handoff.workflow,
      handoff.stage,
      event_id,
      handoff.attrs,
      opts
    )
  end

  defp record_stage_event(%HistoricalWorkflowStageHandoff{event_id: event_id} = handoff, opts)
       when is_binary(event_id) do
    DataManagement.record_historical_data_workflow_stage_transition(
      handoff.workflow,
      handoff.stage,
      event_id,
      handoff.attrs,
      opts
    )
  end

  defp record_stage_event(%HistoricalWorkflowStageHandoff{} = handoff, opts) do
    DataManagement.record_historical_data_workflow_event(
      handoff.workflow,
      handoff.stage,
      handoff.attrs,
      opts
    )
  end

  def record_group_stage(params, scope, mission, opts \\ [])
      when is_map(params) and is_list(opts) do
    with {:ok, %HistoricalWorkflowGroupStageHandoff{} = handoff} <-
           HistoricalWorkflowHandoff.group_stage(params, scope, mission),
         {:ok, group_transition_target} <- group_transition_target(handoff),
         {:ok, events, job_results} <-
           DataManagement.record_historical_data_workflow_group_transition(
             handoff.workflow,
             handoff.stage,
             group_transition_target,
             handoff.attrs,
             opts
           ) do
      {:ok, events, job_results}
    else
      {:error, {:no_eligible_items, failed_stage}} ->
        {:error, {:no_eligible_request_group_items, group_id_for_error(params), failed_stage}}

      {:error, {:request_group_not_found, _request_group_id}} ->
        {:error, {:request_group_not_found, group_id_for_error(params)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def record_request(params, scope, mission, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %HistoricalWorkflowRequestHandoff{} = handoff} <-
           HistoricalWorkflowHandoff.request(params, scope, mission),
         {:ok, events} <-
           DataManagement.record_historical_data_workflow_request(
             handoff.workflow,
             handoff.attrs,
             handoff.point_ids,
             opts
           ) do
      {:ok, events, handoff.selection_params}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def record_correction_request(params, scope, mission, opts \\ [])
      when is_map(params) and is_list(opts) do
    with {:ok, %HistoricalWorkflowCorrectionRequestHandoff{} = handoff} <-
           HistoricalWorkflowHandoff.correction_request(params, scope, mission),
         {:ok, event} <-
           DataManagement.record_historical_data_workflow_correction_request(
             handoff.workflow,
             handoff.attrs,
             handoff.correction_params,
             opts
           ) do
      {:ok, event}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def retry_job(job_id, event_id, scope, mission, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_list(opts) do
    recover_job(:retry_job, job_id, event_id, scope, mission, opts)
  end

  def retry_group_failed_jobs(request_group_id, scope, mission, opts \\ [])
      when is_list(opts) do
    with {:ok, %HistoricalWorkflowRetryGroupFailedJobsHandoff{} = handoff} <-
           HistoricalWorkflowHandoff.retry_group_failed_jobs(request_group_id, scope, mission) do
      DataManagement.retry_historical_data_workflow_group_failed_jobs(
        handoff.request_group_id,
        handoff.actor_attrs,
        opts
      )
    end
  end

  def inspect_stale_replacement_job(job_id, event_id, scope, mission, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_list(opts) do
    recover_job(:inspect_stale_replacement_job, job_id, event_id, scope, mission, opts)
  end

  def inspect_missing_replacement_job(
        request_group_id,
        replacement_run_id,
        scope,
        mission,
        opts \\ []
      )
      when is_binary(request_group_id) and is_binary(replacement_run_id) and is_list(opts) do
    request_group_id = text_param(request_group_id)
    replacement_run_id = text_param(replacement_run_id)

    cond do
      is_nil(request_group_id) ->
        {:error, {:missing_field, :request_group_id}}

      is_nil(replacement_run_id) ->
        {:error, {:missing_field, :replacement_run_id}}

      true ->
        DataManagement.record_historical_data_workflow_missing_replacement_inspection(
          request_group_id,
          replacement_run_id,
          HistoricalWorkflowParams.actor_attrs(scope, mission),
          opts
        )
    end
  end

  def requeue_stale_replacement_job(job_id, event_id, scope, mission, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_list(opts) do
    recover_job(:requeue_stale_replacement_job, job_id, event_id, scope, mission, opts)
  end

  def recover_job(action, job_id, event_id, scope, mission, opts \\ [])
      when is_atom(action) and is_binary(job_id) and is_binary(event_id) and is_list(opts) do
    with {:ok, %HistoricalWorkflowJobRecoveryHandoff{} = handoff} <-
           HistoricalWorkflowHandoff.job_recovery(action, job_id, event_id, scope, mission) do
      run_job_recovery(handoff, opts)
    end
  end

  defp run_job_recovery(%HistoricalWorkflowJobRecoveryHandoff{action: :retry_job} = handoff, opts) do
    DataManagement.retry_historical_data_workflow_job(
      handoff.job_id,
      handoff.event_id,
      handoff.actor_attrs,
      opts
    )
  end

  defp run_job_recovery(
         %HistoricalWorkflowJobRecoveryHandoff{action: :inspect_stale_replacement_job} = handoff,
         opts
       ) do
    DataManagement.record_historical_data_workflow_stale_replacement_inspection(
      handoff.job_id,
      handoff.event_id,
      handoff.actor_attrs,
      opts
    )
  end

  defp run_job_recovery(
         %HistoricalWorkflowJobRecoveryHandoff{action: :requeue_stale_replacement_job} = handoff,
         opts
       ) do
    DataManagement.requeue_historical_data_workflow_stale_replacement_job(
      handoff.job_id,
      handoff.event_id,
      handoff.actor_attrs,
      opts
    )
  end

  defp maybe_start_job("started", workflow, attrs, opts) do
    DataManagement.start_historical_data_workflow_job(workflow, attrs, opts)
  end

  defp maybe_start_job(_stage, _workflow, _attrs, _opts), do: {:ok, nil}

  defp group_transition_target(
         %HistoricalWorkflowGroupStageHandoff{
           group_transition_scope: "replacement_corrections"
         } = handoff
       ) do
    replacement_correction_group_events(handoff)
  end

  defp group_transition_target(%HistoricalWorkflowGroupStageHandoff{} = handoff) do
    {:ok, handoff.request_group_id}
  end

  defp replacement_correction_group_events(%HistoricalWorkflowGroupStageHandoff{} = handoff) do
    run_ids = handoff.replacement_run_ids

    with [_run_id | _run_ids] <- run_ids,
         {:ok, organization_id} <- required_handoff_attr(handoff, :organization_id),
         {:ok, mission_id} <- required_handoff_attr(handoff, :mission_id) do
      run_id_set = MapSet.new(run_ids)

      events =
        mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: organization_id,
          limit: 1_000
        )
        |> Enum.filter(fn event ->
          Storage.BackfillLifecycleGroup.payload_value(event, :request_group_id) ==
            handoff.request_group_id and MapSet.member?(run_id_set, event.backfill_run_id)
        end)

      case events do
        [_event | _events] -> {:ok, events}
        [] -> {:error, {:no_eligible_items, handoff.stage}}
      end
    else
      [] -> {:error, {:no_eligible_items, handoff.stage}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp required_handoff_attr(%HistoricalWorkflowGroupStageHandoff{attrs: attrs}, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, key}}
    end
  end

  defp group_id_for_error(params) do
    params
    |> HistoricalWorkflowParams.request_group_id()
    |> text_param()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
