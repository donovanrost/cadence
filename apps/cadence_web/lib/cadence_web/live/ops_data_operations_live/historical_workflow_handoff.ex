defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowHandoff do
  @moduledoc false

  alias Cadence.Jobs

  alias CadenceWeb.OpsDataOperationsLive.{
    HistoricalWorkflowCorrectionRequestHandoff,
    HistoricalWorkflowGroupStageHandoff,
    HistoricalWorkflowJobRecoveryHandoff,
    HistoricalWorkflowParams,
    HistoricalWorkflowRequestHandoff,
    HistoricalWorkflowRetryGroupFailedJobsHandoff,
    HistoricalWorkflowRetryJobHandoff,
    HistoricalWorkflowStageHandoff,
    HistoricalWorkflowStaleReplacementJobHandoff
  }

  @requested_stage "requested"
  # The lifecycle-event and job `run_id` columns are varchar(255).
  @run_id_bytes 255
  @default_request_workflow "backfill"
  @job_recovery_actions [
    :retry_job,
    :inspect_stale_replacement_job,
    :requeue_stale_replacement_job
  ]

  @type run_id_error :: {:invalid_field, :run_id, :too_large}

  @type t ::
          HistoricalWorkflowStageHandoff.t()
          | HistoricalWorkflowGroupStageHandoff.t()
          | HistoricalWorkflowRequestHandoff.t()
          | HistoricalWorkflowCorrectionRequestHandoff.t()
          | HistoricalWorkflowJobRecoveryHandoff.t()
          | HistoricalWorkflowRetryJobHandoff.t()
          | HistoricalWorkflowRetryGroupFailedJobsHandoff.t()
          | HistoricalWorkflowStaleReplacementJobHandoff.t()

  @spec stage(HistoricalWorkflowParams.t() | map(), map(), map()) ::
          {:ok, HistoricalWorkflowStageHandoff.t()} | {:error, run_id_error()}
  def stage(params, scope, mission) when is_map(params) do
    params = stage_params(params)
    workflow = params.workflow
    stage = params.stage

    with {:ok, selection_params} <-
           params
           |> normalize_workflow_stage(workflow, stage)
           |> new_event_run_id(scope, mission) do
      {:ok,
       %HistoricalWorkflowStageHandoff{
         workflow: workflow,
         stage: stage,
         attrs: HistoricalWorkflowParams.attrs(selection_params, scope, mission),
         event_id: params.event_id,
         correction_source_event_id: params.correction_source_event_id,
         selection_params: HistoricalWorkflowParams.to_event_params(selection_params)
       }}
    end
  end

  @spec group_stage(HistoricalWorkflowParams.t() | map(), map(), map()) ::
          {:ok, HistoricalWorkflowGroupStageHandoff.t()}
          | {:error, {:missing_field, :request_group_id}}
  def group_stage(params, scope, mission) when is_map(params) do
    params = group_stage_params(params)
    workflow = params.workflow
    stage = params.stage

    case HistoricalWorkflowParams.request_group_id(params) do
      request_group_id when is_binary(request_group_id) ->
        selection_params = normalize_workflow_stage(params, workflow, stage)

        {:ok,
         %HistoricalWorkflowGroupStageHandoff{
           workflow: workflow,
           stage: stage,
           attrs: HistoricalWorkflowParams.attrs(selection_params, scope, mission),
           request_group_id: request_group_id,
           group_transition_scope: HistoricalWorkflowParams.get(params, :group_transition_scope),
           group_correction_tasks: HistoricalWorkflowParams.get(params, :group_correction_tasks),
           replacement_run_ids:
             replacement_run_ids(HistoricalWorkflowParams.get(params, :group_correction_tasks)),
           selection_params: HistoricalWorkflowParams.to_event_params(selection_params)
         }}

      nil ->
        {:error, {:missing_field, :request_group_id}}
    end
  end

  @spec request(HistoricalWorkflowParams.t() | map(), map(), map()) ::
          {:ok, HistoricalWorkflowRequestHandoff.t()} | {:error, run_id_error()}
  def request(params, scope, mission) when is_map(params) do
    params = request_params(params)
    workflow = params.workflow || @default_request_workflow

    params =
      params
      |> HistoricalWorkflowParams.put(:workflow, workflow)
      |> HistoricalWorkflowParams.put(:stage, @requested_stage)

    point_ids = HistoricalWorkflowParams.request_point_ids(params)

    with {:ok, selection_params} <- tenant_run_id(params, scope, mission, length(point_ids)) do
      {:ok,
       %HistoricalWorkflowRequestHandoff{
         workflow: workflow,
         stage: @requested_stage,
         attrs: HistoricalWorkflowParams.attrs(selection_params, scope, mission),
         point_ids: point_ids,
         selection_params: HistoricalWorkflowParams.to_event_params(selection_params)
       }}
    end
  end

  @spec correction_request(HistoricalWorkflowParams.t() | map(), map(), map()) ::
          {:ok, HistoricalWorkflowCorrectionRequestHandoff.t()} | {:error, run_id_error()}
  def correction_request(params, scope, mission) when is_map(params) do
    params = correction_params(params)
    workflow = params.workflow

    with {:ok, selection_params} <-
           params
           |> HistoricalWorkflowParams.put(:workflow, workflow)
           |> tenant_run_id(scope, mission) do
      {:ok,
       %HistoricalWorkflowCorrectionRequestHandoff{
         workflow: workflow,
         stage: @requested_stage,
         attrs: HistoricalWorkflowParams.attrs(selection_params, scope, mission),
         correction_params: HistoricalWorkflowParams.to_event_params(params),
         selection_params: HistoricalWorkflowParams.to_event_params(selection_params)
       }}
    end
  end

  @spec retry_job(String.t(), String.t(), map(), map()) ::
          {:ok, HistoricalWorkflowRetryJobHandoff.t()}
          | {:error, {:missing_field, :job_id | :event_id}}
  def retry_job(job_id, event_id, scope, mission) do
    with job_id when is_binary(job_id) <- text_param(job_id),
         event_id when is_binary(event_id) <- text_param(event_id) do
      {:ok,
       %HistoricalWorkflowRetryJobHandoff{
         job_id: job_id,
         event_id: event_id,
         actor_attrs: HistoricalWorkflowParams.actor_attrs(scope, mission)
       }}
    else
      nil ->
        missing_retry_job_field(job_id, event_id)
    end
  end

  @spec supported_job_recovery_actions() :: [HistoricalWorkflowJobRecoveryHandoff.action()]
  def supported_job_recovery_actions, do: @job_recovery_actions

  @spec job_recovery(
          HistoricalWorkflowJobRecoveryHandoff.action() | atom(),
          String.t(),
          String.t(),
          map(),
          map()
        ) ::
          {:ok, HistoricalWorkflowJobRecoveryHandoff.t()}
          | {:error, {:missing_field, :job_id | :event_id}}
          | {:error, {:unsupported_job_recovery_action, atom()}}
  def job_recovery(action, job_id, event_id, scope, mission)
      when action in [
             :retry_job,
             :inspect_stale_replacement_job,
             :requeue_stale_replacement_job
           ] do
    with job_id when is_binary(job_id) <- text_param(job_id),
         event_id when is_binary(event_id) <- text_param(event_id) do
      {:ok,
       %HistoricalWorkflowJobRecoveryHandoff{
         action: action,
         job_id: job_id,
         event_id: event_id,
         actor_attrs: HistoricalWorkflowParams.actor_attrs(scope, mission)
       }}
    else
      nil ->
        missing_retry_job_field(job_id, event_id)
    end
  end

  def job_recovery(action, _job_id, _event_id, _scope, _mission) when is_atom(action) do
    {:error, {:unsupported_job_recovery_action, action}}
  end

  @spec stale_replacement_job(String.t(), String.t(), map(), map()) ::
          {:ok, HistoricalWorkflowStaleReplacementJobHandoff.t()}
          | {:error, {:missing_field, :job_id | :event_id}}
  def stale_replacement_job(job_id, event_id, scope, mission) do
    with job_id when is_binary(job_id) <- text_param(job_id),
         event_id when is_binary(event_id) <- text_param(event_id) do
      {:ok,
       %HistoricalWorkflowStaleReplacementJobHandoff{
         job_id: job_id,
         event_id: event_id,
         actor_attrs: HistoricalWorkflowParams.actor_attrs(scope, mission)
       }}
    else
      nil ->
        missing_retry_job_field(job_id, event_id)
    end
  end

  @spec retry_group_failed_jobs(String.t(), map(), map()) ::
          {:ok, HistoricalWorkflowRetryGroupFailedJobsHandoff.t()}
          | {:error, {:missing_field, :request_group_id}}
  def retry_group_failed_jobs(request_group_id, scope, mission) do
    case text_param(request_group_id) do
      request_group_id when is_binary(request_group_id) ->
        {:ok,
         %HistoricalWorkflowRetryGroupFailedJobsHandoff{
           request_group_id: request_group_id,
           actor_attrs: HistoricalWorkflowParams.actor_attrs(scope, mission)
         }}

      nil ->
        {:error, {:missing_field, :request_group_id}}
    end
  end

  defp stage_params(%HistoricalWorkflowParams{} = params), do: params
  defp stage_params(params) when is_map(params), do: HistoricalWorkflowParams.event_params(params)

  defp group_stage_params(%HistoricalWorkflowParams{} = params), do: params

  defp group_stage_params(params) when is_map(params),
    do: HistoricalWorkflowParams.group_params(params)

  defp request_params(%HistoricalWorkflowParams{} = params), do: params

  defp request_params(params) when is_map(params),
    do: HistoricalWorkflowParams.request_params(params)

  defp correction_params(%HistoricalWorkflowParams{} = params), do: params

  defp correction_params(params) when is_map(params),
    do: HistoricalWorkflowParams.correction_params(params)

  defp normalize_workflow_stage(params, workflow, stage) do
    params
    |> HistoricalWorkflowParams.put(:workflow, workflow)
    |> HistoricalWorkflowParams.put(:stage, stage)
  end

  # A stage without a source event records a new event under the client's run id; with one, the
  # run id comes from that event.
  defp new_event_run_id(%HistoricalWorkflowParams{event_id: nil} = params, scope, mission),
    do: tenant_run_id(params, scope, mission)

  defp new_event_run_id(params, _scope, _mission), do: {:ok, params}

  # Jobs are unique per run id across every organization, so a client-chosen run id that starts
  # a run is namespaced to the tenant (`Cadence.Jobs.tenant_run_id/3`). No run id: the server
  # mints one. The namespaced id, and every request item derived from it (`<id>-001` when there
  # is more than one point), must fit the run_id column: 243 bytes of client id for one point,
  # 239 for up to 999 points.
  defp tenant_run_id(params, scope, mission, item_count \\ 1) do
    case {params.run_id, Map.get(scope, :organization_id), Map.get(mission, :mission_id)} do
      {run_id, organization_id, mission_id}
      when is_binary(run_id) and is_binary(organization_id) and is_binary(mission_id) ->
        run_id = Jobs.tenant_run_id(organization_id, mission_id, run_id)

        if byte_size(run_id) + item_suffix_bytes(item_count) <= @run_id_bytes,
          do: {:ok, HistoricalWorkflowParams.put(params, :run_id, run_id)},
          else: {:error, {:invalid_field, :run_id, :too_large}}

      _unscoped ->
        {:ok, params}
    end
  end

  defp item_suffix_bytes(item_count) when item_count <= 1, do: 0

  defp item_suffix_bytes(item_count),
    do: 1 + max(3, item_count |> Integer.to_string() |> byte_size())

  defp replacement_run_ids(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.flat_map(&replacement_run_id/1)
    |> Enum.uniq()
  end

  defp replacement_run_ids(_value), do: []

  defp replacement_run_id(task) do
    case String.split(task, " replacement ", parts: 2) do
      [_prefix, replacement] ->
        replacement
        |> String.split(" stage ", parts: 2)
        |> List.first()
        |> text_param()
        |> case do
          nil -> []
          run_id -> [run_id]
        end

      _other ->
        []
    end
  end

  defp missing_retry_job_field(job_id, _event_id) when not is_binary(job_id),
    do: {:error, {:missing_field, :job_id}}

  defp missing_retry_job_field(job_id, _event_id) when is_binary(job_id) do
    if text_param(job_id),
      do: {:error, {:missing_field, :event_id}},
      else: {:error, {:missing_field, :job_id}}
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
