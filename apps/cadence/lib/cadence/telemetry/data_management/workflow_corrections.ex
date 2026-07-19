defmodule Cadence.Telemetry.DataManagement.WorkflowCorrections do
  @moduledoc """
  Correction requests and stage transitions for historical telemetry workflows.

  This boundary owns correction-source validation, supersession checks, action
  policy enforcement, and the payload lineage carried through correction
  lifecycle events.
  """

  alias Cadence.Jobs
  alias Cadence.Telemetry.DataManagement.WorkflowEventEvidence
  alias Cadence.Telemetry.DataManagement.WorkflowEvents
  alias Cadence.Telemetry.DataManagement.WorkflowPolicy
  alias Cadence.Telemetry.Storage

  @spec record_request(atom() | binary(), map(), map(), keyword()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_request(workflow, attrs, correction, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_map(correction) and
             is_list(opts) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         {:ok, source_event} <- source_event(correction, attrs),
         :ok <- require_source(workflow, source_event),
         :ok <- require_source_open(source_event),
         :ok <- require_request_policy(source_event) do
      attrs =
        attrs
        |> correction_attrs(source_event, correction)
        |> compact_attrs()

      WorkflowEvents.record(workflow, :requested, attrs, opts)
    end
  end

  @spec record_transition(atom() | binary(), atom() | binary(), binary(), map(), keyword()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_transition(workflow, stage, correction_event_id, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(correction_event_id) and is_map(attrs) and is_list(opts) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         {:ok, stage} <- WorkflowEvents.normalize_stage(stage),
         {:ok, correction_event} <- WorkflowEventEvidence.fetch(correction_event_id, attrs) do
      transition_event(workflow, stage, correction_event, attrs, opts)
    end
  end

  @spec transition_event(atom(), atom(), Storage.BackfillLifecycleEvent.t(), map(), keyword()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def transition_event(workflow, stage, correction_event, attrs, opts)
      when is_atom(workflow) and is_atom(stage) and is_map(attrs) and is_list(opts) do
    with :ok <- require_correction_event(workflow, correction_event, attrs),
         :ok <- require_transition_policy(stage, correction_event) do
      correction_event
      |> transition_attrs(attrs)
      |> then(&WorkflowEvents.record(workflow, stage, &1, opts))
    end
  end

  defp source_event(correction, attrs) do
    with {:ok, event_id} <- source_event_id(correction),
         {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id) do
      case Storage.fetch_backfill_lifecycle_event(event_id,
             organization_id: organization_id,
             mission_id: mission_id
           ) do
        %Storage.BackfillLifecycleEvent{} = event -> {:ok, event}
        nil -> {:error, {:historical_workflow_correction_source_not_found, event_id}}
      end
    end
  end

  defp source_event_id(correction) do
    case get_attr(correction, :original_event_id) do
      event_id when is_binary(event_id) and event_id != "" -> {:ok, event_id}
      _event_id -> {:error, {:missing_field, :original_event_id}}
    end
  end

  defp correction_event_source_event_id(correction_event) do
    case Storage.BackfillLifecycleGroup.payload_value(correction_event, :corrects_event_id) do
      event_id when is_binary(event_id) and event_id != "" ->
        {:ok, event_id}

      _event_id ->
        {:error,
         {:invalid_historical_workflow_correction_event,
          correction_event.backfill_lifecycle_event_id, :missing_source_event}}
    end
  end

  defp require_source(workflow, source_event) do
    cond do
      source_event.event_type not in [:backfill_failed, :import_failed] ->
        {:error,
         {:invalid_historical_workflow_correction_source,
          source_event.backfill_lifecycle_event_id, :not_failed}}

      source_workflow(source_event) != workflow ->
        {:error,
         {:invalid_historical_workflow_correction_source,
          source_event.backfill_lifecycle_event_id, :workflow_mismatch}}

      WorkflowEventEvidence.recovery_action(source_event) != "correct_workflow_request" ->
        {:error,
         {:invalid_historical_workflow_correction_source,
          source_event.backfill_lifecycle_event_id, :correction_not_required}}

      true ->
        :ok
    end
  end

  defp require_source_open(source_event) do
    if source_superseded?(source_event) do
      {:error,
       {:historical_workflow_correction_source_superseded,
        source_event.backfill_lifecycle_event_id}}
    else
      :ok
    end
  end

  defp require_request_policy(source_event) do
    with {:ok, job} <- source_job(source_event) do
      decision =
        source_event
        |> request_policy_context(job)
        |> WorkflowPolicy.correction_request_action_policy()

      if decision.eligible? do
        :ok
      else
        {:error,
         {:historical_workflow_correction_request_blocked,
          source_event.backfill_lifecycle_event_id, decision.reason}}
      end
    end
  end

  defp source_job(source_event) do
    error_tag = :historical_workflow_correction_request_blocked

    with {:ok, job} <- fetch_job_for_source_event(source_event, error_tag),
         :ok <- require_source_event_job_match(source_event, job, error_tag) do
      {:ok, job}
    end
  end

  defp request_policy_context(source_event, %Jobs.Job{} = job) do
    %{
      event_id: source_event.backfill_lifecycle_event_id,
      job_id: job.job_id,
      job_status: Atom.to_string(job.status),
      recovery_action: WorkflowEventEvidence.recovery_action(source_event)
    }
  end

  defp require_correction_event(workflow, correction_event, attrs) do
    with {:ok, source_event_id} <- correction_event_source_event_id(correction_event),
         {:ok, source_event} <-
           source_event(%{"original_event_id" => source_event_id}, attrs),
         :ok <- require_source(workflow, source_event) do
      require_source_open(source_event)
    end
  end

  defp source_superseded?(source_event) do
    source_event.mission_id
    |> Storage.list_backfill_lifecycle_events(
      organization_id: source_event.organization_id,
      limit: 1_000
    )
    |> Enum.any?(fn event ->
      Storage.BackfillLifecycleGroup.payload_value(event, :corrects_event_id) ==
        source_event.backfill_lifecycle_event_id and
        Storage.BackfillLifecycleGroup.payload_value(event, :stage) == "completed"
    end)
  end

  defp source_workflow(source_event) do
    source_event
    |> WorkflowEventEvidence.workflow()
    |> WorkflowEvents.normalize_workflow()
    |> case do
      {:ok, workflow} -> workflow
      {:error, _reason} -> nil
    end
  end

  defp correction_attrs(attrs, source_event, correction) do
    source_event
    |> correction_source_attrs()
    |> Enum.reduce(attrs, fn {key, source_value}, attrs ->
      put_compact_attr(attrs, key, source_value || get_attr(attrs, key))
    end)
    |> Map.put(:payload, correction_payload(source_event, correction))
  end

  defp correction_source_attrs(source_event) do
    [
      realm: source_event.realm,
      data_source_id: source_event.data_source_id,
      binding_id: source_event.binding_id,
      observable_id: source_event.observable_id,
      point_id: source_event.point_id,
      source_from: source_event.source_from,
      source_to: source_event.source_to,
      receipt_from: source_event.receipt_from,
      receipt_to: source_event.receipt_to
    ]
  end

  defp correction_payload(source_event, correction) do
    source_event.payload
    |> Map.take([
      "request_source",
      "request_mode",
      "request_group_id",
      "request_item_index",
      "request_item_count",
      "request_item_run_id",
      "dashboard_context",
      "comparison_review_origin"
    ])
    |> Map.merge(correction_request_context(correction))
    |> Map.merge(%{
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => Atom.to_string(source_event.event_type),
      "recovery_action" => "correct_workflow_request",
      "corrects_run_id" =>
        text_attr(correction, :original_run_id) || source_event.backfill_run_id,
      "corrects_event_id" => source_event.backfill_lifecycle_event_id,
      "corrects_job_id" =>
        text_attr(correction, :original_job_id) || WorkflowEventEvidence.job_id(source_event)
    })
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp correction_request_context(correction) do
    %{}
    |> put_compact_attr("request_mode", text_attr(correction, :request_mode))
    |> put_compact_attr("request_group_id", text_attr(correction, :request_group_id))
    |> put_compact_attr("dashboard_context", dashboard_context(correction))
    |> put_compact_attr("request_item_index", integer_attr(correction, :request_item_index))
    |> put_compact_attr("request_item_count", integer_attr(correction, :request_item_count))
    |> put_compact_attr("request_item_run_id", text_attr(correction, :request_item_run_id))
  end

  defp dashboard_context(correction) do
    %{
      "dashboard_id" => text_attr(correction, :dashboard_id),
      "dashboard_version" => text_attr(correction, :dashboard_version),
      "dashboard_time_mode" => text_attr(correction, :dashboard_time_mode),
      "dashboard_replay_run_id" => text_attr(correction, :dashboard_replay_run_id),
      "dashboard_data_view" => text_attr(correction, :dashboard_data_view),
      "dashboard_limit_mode" => text_attr(correction, :dashboard_limit_mode)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> empty_map_to_nil()
  end

  defp empty_map_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(map), do: map

  defp text_attr(attrs, key) do
    case get_attr(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp integer_attr(attrs, key) do
    case get_attr(attrs, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> nil
        end

      _value ->
        nil
    end
  end

  defp require_transition_policy(stage, correction_event) do
    decision =
      correction_event
      |> transition_policy_context()
      |> WorkflowPolicy.stage_action_policy(stage)

    if decision.eligible? do
      :ok
    else
      {:error,
       {:historical_workflow_correction_transition_blocked,
        correction_event.backfill_lifecycle_event_id, decision.reason}}
    end
  end

  defp transition_policy_context(correction_event) do
    correction_event
    |> transition_job_context()
    |> Map.put(:stage, Storage.BackfillLifecycleGroup.payload_value(correction_event, :stage))
  end

  defp transition_job_context(correction_event) do
    case Jobs.fetch_job_for_run(
           :telemetry_historical_data_workflow,
           correction_event.backfill_run_id
         ) do
      {:ok, %{job_id: job_id, status: status}} ->
        %{job_id: job_id, job_status: Atom.to_string(status)}

      {:error, _reason} ->
        %{}
    end
  end

  defp transition_attrs(event, attrs) do
    attrs
    |> put_compact_attr(:backfill_run_id, event.backfill_run_id)
    |> put_compact_attr(:import_run_id, event.backfill_run_id)
    |> put_compact_attr(:realm, event.realm || get_attr(attrs, :realm))
    |> put_compact_attr(:data_source_id, event.data_source_id || get_attr(attrs, :data_source_id))
    |> put_compact_attr(:binding_id, event.binding_id || get_attr(attrs, :binding_id))
    |> put_compact_attr(:observable_id, event.observable_id || get_attr(attrs, :observable_id))
    |> put_compact_attr(:point_id, event.point_id || get_attr(attrs, :point_id))
    |> put_compact_attr(:source_from, event.source_from || get_attr(attrs, :source_from))
    |> put_compact_attr(:source_to, event.source_to || get_attr(attrs, :source_to))
    |> put_compact_attr(:payload, transition_payload(event, attrs))
    |> compact_attrs()
  end

  defp transition_payload(event, attrs) do
    transition_payload =
      attrs
      |> get_attr(:payload, %{})
      |> ensure_map()
      |> Map.take([
        "dashboard_context",
        "comparison_review_origin",
        "group_transition_source",
        "group_transition_scope"
      ])

    event.payload
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
      "requested_event_id",
      "dashboard_context",
      "comparison_review_origin"
    ])
    |> Map.merge(transition_payload)
    |> Map.put_new("requested_event_id", event.backfill_lifecycle_event_id)
    |> Map.put("correction_transition_source", "dashboard_correction_transition")
    |> Map.put("correction_transition_source_event_id", event.backfill_lifecycle_event_id)
  end

  defp fetch_job_for_source_event(source_event, error_tag) do
    case source_event.backfill_run_id do
      run_id when is_binary(run_id) and run_id != "" ->
        case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
          {:ok, %Jobs.Job{} = job} ->
            {:ok, job}

          {:error, _reason} ->
            {:error, {error_tag, source_event.backfill_lifecycle_event_id, "job_status_missing"}}
        end

      _run_id ->
        {:error, {error_tag, source_event.backfill_lifecycle_event_id, "job_status_missing"}}
    end
  end

  defp require_source_event_job_match(source_event, %Jobs.Job{} = job, error_tag) do
    case WorkflowEventEvidence.job_id(source_event) do
      event_job_id
      when is_binary(event_job_id) and event_job_id != "" and event_job_id != job.job_id ->
        {:error, {error_tag, source_event.backfill_lifecycle_event_id, :job_id_mismatch}}

      _event_job_id ->
        :ok
    end
  end

  defp required_attr(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp put_compact_attr(attrs, _key, value) when value in [nil, ""], do: attrs
  defp put_compact_attr(attrs, key, value), do: Map.put(attrs, key, value)

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
