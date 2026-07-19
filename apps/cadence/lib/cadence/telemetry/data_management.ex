defmodule Cadence.Telemetry.DataManagement do
  @moduledoc """
  Product-level telemetry data-management workflows.

  Storage owns observation persistence. This module owns workflow-shaped entry
  points such as backfill/import sample writes that should emit lifecycle events
  visible to dashboards.
  """

  alias Cadence.Jobs
  alias Cadence.Telemetry.DataManagement.LateDataPolicy
  alias Cadence.Telemetry.DataManagement.ObservationIdentityDecisions
  alias Cadence.Telemetry.DataManagement.WorkflowEvents
  alias Cadence.Telemetry.DataManagement.WorkflowJobs
  alias Cadence.Telemetry.DataManagement.WorkflowPolicy
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.ObservationIdentityState

  @type workflow_attrs :: map()
  @type observation_identity_decision ::
          :mark_canonical | :mark_conflict | :mark_superseded | :mark_advisory
  @type late_data_policy_decision :: :accept | :reject
  @type historical_data_workflow :: :backfill | :import
  @type historical_data_workflow_stage ::
          :requested | :approved | :rejected | :started | :completed | :failed | :retried
  @type historical_data_workflow_group_retry_summary :: %{
          retried: non_neg_integer(),
          nonretryable: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer(),
          nonretryable_items: [historical_data_workflow_group_retry_item()],
          skipped_items: [historical_data_workflow_group_retry_item()],
          retry_error_items: [historical_data_workflow_group_retry_error_item()],
          events: [Storage.BackfillLifecycleEvent.t()]
        }
  @type historical_data_workflow_group_retry_item :: %{
          run_id: binary() | nil,
          event_id: binary() | nil,
          job_id: binary() | nil,
          job_status: binary() | nil,
          reason: binary()
        }
  @type historical_data_workflow_group_retry_error_item :: %{
          run_id: binary() | nil,
          event_id: binary() | nil,
          job_id: binary() | nil,
          reason: binary()
        }
  @type historical_data_workflow_action_decision :: %{
          optional(:eligible_count) => non_neg_integer(),
          id: binary(),
          kind: atom(),
          eligible?: boolean(),
          disabled?: boolean(),
          reason: binary()
        }
  @type historical_data_workflow_explanation_summary :: %{
          severity: :success | :warning | :error | :info,
          state: binary(),
          badge: binary(),
          reason: binary()
        }
  @type late_data_policy_execution_result :: %{
          event: Storage.BackfillLifecycleEvent.t(),
          sample_count: non_neg_integer(),
          diagnostics: map()
        }
  @type late_data_policy_execution_mode :: :sample_execution | :event_only
  @type observation_identity_decision_batch_summary :: %{
          decision: observation_identity_decision(),
          workflow_id: binary() | nil,
          requested: non_neg_integer(),
          applied: non_neg_integer(),
          failed: non_neg_integer(),
          results: [map()],
          errors: [map()]
        }

  @stale_historical_data_workflow_job_seconds 15 * 60

  @spec backfill_samples([Sample.t()], workflow_attrs(), keyword()) :: :ok | {:error, term()}
  def backfill_samples(samples, attrs, opts \\ [])
      when is_list(samples) and is_map(attrs) and is_list(opts) do
    execute_sample_workflow(:backfill, samples, attrs, opts)
  end

  @spec import_samples([Sample.t()], workflow_attrs(), keyword()) :: :ok | {:error, term()}
  def import_samples(samples, attrs, opts \\ [])
      when is_list(samples) and is_map(attrs) and is_list(opts) do
    execute_sample_workflow(:import, samples, attrs, opts)
  end

  @spec record_historical_data_workflow_event(
          historical_data_workflow() | binary(),
          historical_data_workflow_stage() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_historical_data_workflow_event(workflow, stage, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_map(attrs) and is_list(opts) do
    WorkflowEvents.record(workflow, stage, attrs, opts)
  end

  @spec record_historical_data_workflow_request(
          historical_data_workflow() | binary(),
          workflow_attrs(),
          [binary() | nil],
          keyword()
        ) ::
          {:ok, [Storage.BackfillLifecycleEvent.t()]} | {:error, term()}
  def record_historical_data_workflow_request(workflow, attrs, point_ids, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(point_ids) and
             is_list(opts) do
    WorkflowEvents.record_request(workflow, attrs, point_ids, opts)
  end

  @spec record_historical_data_workflow_correction_request(
          historical_data_workflow() | binary(),
          workflow_attrs(),
          map(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_historical_data_workflow_correction_request(workflow, attrs, correction, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_map(correction) and
             is_list(opts) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         {:ok, source_event} <-
           historical_data_workflow_correction_source_event(correction, attrs),
         :ok <- require_historical_data_workflow_correction_source(workflow, source_event),
         :ok <- require_historical_data_workflow_correction_source_open(source_event),
         :ok <- require_historical_data_workflow_correction_request_policy(source_event) do
      attrs =
        attrs
        |> historical_data_workflow_correction_attrs(source_event, correction)
        |> compact_attrs()

      record_historical_data_workflow_event(workflow, :requested, attrs, opts)
    end
  end

  @spec record_historical_data_workflow_correction_transition(
          historical_data_workflow() | binary(),
          historical_data_workflow_stage() | binary(),
          binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_historical_data_workflow_correction_transition(
        workflow,
        stage,
        correction_event_id,
        attrs,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(correction_event_id) and is_map(attrs) and is_list(opts) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         {:ok, stage} <- WorkflowEvents.normalize_stage(stage),
         {:ok, correction_event} <-
           fetch_historical_data_workflow_event(correction_event_id, attrs) do
      record_historical_data_workflow_correction_transition_event(
        workflow,
        stage,
        correction_event,
        attrs,
        opts
      )
    end
  end

  @spec record_historical_data_workflow_stage_transition(
          historical_data_workflow() | binary(),
          historical_data_workflow_stage() | binary(),
          binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_historical_data_workflow_stage_transition(
        workflow,
        stage,
        source_event_id,
        attrs,
        opts \\ []
      )
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_binary(source_event_id) and is_map(attrs) and is_list(opts) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         {:ok, stage} <- WorkflowEvents.normalize_stage(stage),
         {:ok, source_event} <- fetch_historical_data_workflow_event(source_event_id, attrs),
         :ok <- require_historical_data_workflow_transition_source(workflow, stage, source_event),
         :ok <- require_historical_data_workflow_stage_transition_policy(stage, source_event) do
      record_historical_data_workflow_transition_event(
        workflow,
        stage,
        source_event,
        historical_data_workflow_stage_transition_attrs(source_event, attrs),
        opts
      )
    end
  end

  @spec historical_data_workflow_action_policy(map()) :: %{
          retry_job: historical_data_workflow_action_decision(),
          retry_group_failed_jobs: historical_data_workflow_action_decision(),
          correction_request: historical_data_workflow_action_decision()
        }
  def historical_data_workflow_action_policy(context), do: WorkflowPolicy.action_policy(context)

  @spec historical_data_workflow_stage_action_policy(map(), atom() | binary()) ::
          historical_data_workflow_action_decision()
  def historical_data_workflow_stage_action_policy(context, stage),
    do: WorkflowPolicy.stage_action_policy(context, stage)

  @spec historical_data_workflow_group_stage_action_policy(map(), atom() | binary()) ::
          historical_data_workflow_action_decision()
  def historical_data_workflow_group_stage_action_policy(context, stage),
    do: WorkflowPolicy.group_stage_action_policy(context, stage)

  @spec historical_data_workflow_explanation_summary(map()) ::
          historical_data_workflow_explanation_summary()
  def historical_data_workflow_explanation_summary(context),
    do: WorkflowPolicy.explanation_summary(context)

  defp historical_data_workflow_correction_source_event(correction, attrs) do
    with {:ok, event_id} <- historical_data_workflow_correction_source_event_id(correction),
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

  defp historical_data_workflow_correction_source_event_id(correction) do
    case get_attr(correction, :original_event_id) do
      event_id when is_binary(event_id) and event_id != "" -> {:ok, event_id}
      _event_id -> {:error, {:missing_field, :original_event_id}}
    end
  end

  defp historical_data_workflow_correction_event_source_event_id(correction_event) do
    case Storage.BackfillLifecycleGroup.payload_value(correction_event, :corrects_event_id) do
      event_id when is_binary(event_id) and event_id != "" ->
        {:ok, event_id}

      _event_id ->
        {:error,
         {:invalid_historical_workflow_correction_event,
          correction_event.backfill_lifecycle_event_id, :missing_source_event}}
    end
  end

  defp require_historical_data_workflow_correction_source(workflow, source_event) do
    cond do
      source_event.event_type not in [:backfill_failed, :import_failed] ->
        {:error,
         {:invalid_historical_workflow_correction_source,
          source_event.backfill_lifecycle_event_id, :not_failed}}

      historical_data_workflow_correction_source_workflow(source_event) != workflow ->
        {:error,
         {:invalid_historical_workflow_correction_source,
          source_event.backfill_lifecycle_event_id, :workflow_mismatch}}

      historical_data_workflow_event_recovery_action(source_event) != "correct_workflow_request" ->
        {:error,
         {:invalid_historical_workflow_correction_source,
          source_event.backfill_lifecycle_event_id, :correction_not_required}}

      true ->
        :ok
    end
  end

  defp require_historical_data_workflow_correction_source_open(source_event) do
    if historical_data_workflow_correction_source_superseded?(source_event) do
      {:error,
       {:historical_workflow_correction_source_superseded,
        source_event.backfill_lifecycle_event_id}}
    else
      :ok
    end
  end

  defp require_historical_data_workflow_correction_request_policy(source_event) do
    with {:ok, job} <- historical_data_workflow_correction_source_job(source_event) do
      decision =
        source_event
        |> historical_data_workflow_correction_request_policy_context(job)
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

  defp historical_data_workflow_correction_source_job(source_event) do
    with {:ok, job} <-
           fetch_historical_data_workflow_job_for_source_event(
             source_event,
             :historical_workflow_correction_request_blocked
           ),
         :ok <-
           require_historical_data_workflow_source_event_job_match(
             source_event,
             job,
             :historical_workflow_correction_request_blocked
           ) do
      {:ok, job}
    end
  end

  defp historical_data_workflow_correction_request_policy_context(source_event, %Jobs.Job{} = job) do
    %{
      event_id: source_event.backfill_lifecycle_event_id,
      job_id: job.job_id,
      job_status: Atom.to_string(job.status),
      recovery_action: historical_data_workflow_event_recovery_action(source_event)
    }
  end

  defp require_historical_data_workflow_correction_event(workflow, correction_event, attrs) do
    with {:ok, source_event_id} <-
           historical_data_workflow_correction_event_source_event_id(correction_event),
         {:ok, source_event} <-
           historical_data_workflow_correction_source_event(
             %{"original_event_id" => source_event_id},
             attrs
           ),
         :ok <- require_historical_data_workflow_correction_source(workflow, source_event) do
      require_historical_data_workflow_correction_source_open(source_event)
    end
  end

  defp historical_data_workflow_correction_source_superseded?(source_event) do
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

  defp historical_data_workflow_correction_source_workflow(source_event) do
    source_event
    |> historical_data_workflow_event_workflow()
    |> WorkflowEvents.normalize_workflow()
    |> case do
      {:ok, workflow} -> workflow
      {:error, _reason} -> nil
    end
  end

  defp historical_data_workflow_correction_attrs(attrs, source_event, correction) do
    source_event
    |> historical_data_workflow_correction_source_attrs()
    |> Enum.reduce(attrs, fn {key, source_value}, attrs ->
      put_compact_attr(attrs, key, source_value || get_attr(attrs, key))
    end)
    |> Map.put(:payload, historical_data_workflow_correction_payload(source_event, correction))
  end

  defp historical_data_workflow_correction_source_attrs(source_event) do
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

  defp historical_data_workflow_correction_payload(source_event, correction) do
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
    |> Map.merge(historical_data_workflow_correction_request_context(correction))
    |> Map.merge(%{
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => Atom.to_string(source_event.event_type),
      "recovery_action" => "correct_workflow_request",
      "corrects_run_id" =>
        correction_text_attr(correction, :original_run_id) || source_event.backfill_run_id,
      "corrects_event_id" => source_event.backfill_lifecycle_event_id,
      "corrects_job_id" =>
        correction_text_attr(correction, :original_job_id) ||
          historical_data_workflow_event_job_id(source_event)
    })
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp historical_data_workflow_correction_request_context(correction) do
    %{}
    |> put_compact_attr("request_mode", correction_text_attr(correction, :request_mode))
    |> put_compact_attr("request_group_id", correction_text_attr(correction, :request_group_id))
    |> put_compact_attr("dashboard_context", correction_dashboard_context(correction))
    |> put_compact_attr(
      "request_item_index",
      correction_integer_attr(correction, :request_item_index)
    )
    |> put_compact_attr(
      "request_item_count",
      correction_integer_attr(correction, :request_item_count)
    )
    |> put_compact_attr(
      "request_item_run_id",
      correction_text_attr(correction, :request_item_run_id)
    )
  end

  defp correction_dashboard_context(correction) do
    %{
      "dashboard_id" => correction_text_attr(correction, :dashboard_id),
      "dashboard_version" => correction_text_attr(correction, :dashboard_version),
      "dashboard_time_mode" => correction_text_attr(correction, :dashboard_time_mode),
      "dashboard_replay_run_id" => correction_text_attr(correction, :dashboard_replay_run_id),
      "dashboard_data_view" => correction_text_attr(correction, :dashboard_data_view),
      "dashboard_limit_mode" => correction_text_attr(correction, :dashboard_limit_mode)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> empty_map_to_nil()
  end

  defp empty_map_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(map), do: map

  defp historical_data_workflow_event_job_id(%{payload: payload}) when is_map(payload) do
    case first_nested_map_value(payload, [["job_id"], [:job_id]]) do
      {:ok, job_id} -> job_id
      :error -> nil
    end
  end

  defp historical_data_workflow_event_job_id(_event), do: nil

  defp correction_text_attr(attrs, key) do
    case get_attr(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp correction_integer_attr(attrs, key) do
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

  defp correction_lifecycle_event?(event) do
    case Storage.BackfillLifecycleGroup.payload_value(event, :corrects_event_id) do
      event_id when is_binary(event_id) and event_id != "" -> true
      _event_id -> false
    end
  end

  defp require_historical_data_workflow_transition_source(workflow, stage, source_event) do
    cond do
      historical_data_workflow_correction_source_workflow(source_event) != workflow ->
        {:error,
         {:invalid_historical_workflow_transition_source,
          source_event.backfill_lifecycle_event_id, :workflow_mismatch}}

      Storage.BackfillLifecycleGroup.payload_value(source_event, :stage) == Atom.to_string(stage) ->
        {:error,
         {:historical_workflow_stage_transition_blocked, source_event.backfill_lifecycle_event_id,
          "already_in_stage"}}

      true ->
        :ok
    end
  end

  defp require_historical_data_workflow_stage_transition_policy(stage, source_event) do
    decision =
      source_event
      |> historical_data_workflow_stage_transition_policy_context()
      |> historical_data_workflow_stage_action_policy(stage)

    if decision.eligible? do
      :ok
    else
      {:error,
       {:historical_workflow_stage_transition_blocked, source_event.backfill_lifecycle_event_id,
        decision.reason}}
    end
  end

  defp historical_data_workflow_stage_transition_policy_context(source_event) do
    source_event
    |> historical_data_workflow_stage_transition_job_context()
    |> Map.put(:stage, Storage.BackfillLifecycleGroup.payload_value(source_event, :stage))
  end

  defp historical_data_workflow_stage_transition_job_context(source_event) do
    case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, source_event.backfill_run_id) do
      {:ok, %{job_id: job_id, status: status}} ->
        %{job_id: job_id, job_status: Atom.to_string(status)}

      {:error, _reason} ->
        %{}
    end
  end

  @spec record_historical_data_workflow_group_transition(
          historical_data_workflow() | binary(),
          historical_data_workflow_stage() | binary(),
          binary() | [Storage.BackfillLifecycleEvent.t()],
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, [Storage.BackfillLifecycleEvent.t()], [term()]} | {:error, term()}
  def record_historical_data_workflow_group_transition(
        workflow,
        stage,
        group_events,
        attrs,
        opts \\ []
      )
      when is_map(attrs) and is_list(opts) do
    with {:ok, workflow} <- WorkflowEvents.normalize_workflow(workflow),
         {:ok, stage} <- WorkflowEvents.normalize_stage(stage),
         {:ok, group_events} <- historical_data_workflow_group_events(group_events, attrs),
         {:ok, transition_sources} <-
           Storage.BackfillLifecycleGroup.transition_sources(
             group_events,
             Atom.to_string(stage)
           ) do
      transition_sources
      |> Enum.reduce_while({:ok, [], []}, fn transition_source, acc ->
        record_historical_data_workflow_group_transition_event(
          transition_source,
          acc,
          workflow,
          stage,
          attrs,
          opts
        )
      end)
      |> historical_data_workflow_group_transition_result()
    end
  end

  defp historical_data_workflow_group_events(group_events, _attrs) when is_list(group_events),
    do: {:ok, group_events}

  defp historical_data_workflow_group_events(request_group_id, attrs)
       when is_binary(request_group_id) do
    with {:ok, request_group_id} <- normalize_request_group_id(request_group_id),
         {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id) do
      mission_id
      |> Storage.list_backfill_lifecycle_events(
        organization_id: organization_id,
        limit: 1_000
      )
      |> Enum.filter(
        &(Storage.BackfillLifecycleGroup.payload_value(&1, :request_group_id) ==
            request_group_id)
      )
      |> case do
        [_event | _events] = group_events -> {:ok, group_events}
        [] -> {:error, {:request_group_not_found, request_group_id}}
      end
    end
  end

  defp historical_data_workflow_group_events(_request_group_id, _attrs),
    do: {:error, {:missing_field, :request_group_id}}

  defp fetch_historical_data_workflow_event(event_id, attrs) do
    with {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id) do
      case Storage.fetch_backfill_lifecycle_event(event_id,
             organization_id: organization_id,
             mission_id: mission_id
           ) do
        %Storage.BackfillLifecycleEvent{} = event -> {:ok, event}
        nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      end
    end
  end

  defp normalize_request_group_id(request_group_id) when is_binary(request_group_id) do
    request_group_id = String.trim(request_group_id)

    if request_group_id == "" do
      {:error, {:missing_field, :request_group_id}}
    else
      {:ok, request_group_id}
    end
  end

  @spec start_historical_data_workflow_job(
          historical_data_workflow() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Jobs.Job.t()} | {:error, term()}
  def start_historical_data_workflow_job(workflow, attrs, _opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) do
    WorkflowJobs.start(workflow, attrs)
  end

  @spec retry_historical_data_workflow_job(binary(), binary(), workflow_attrs(), keyword()) ::
          {:ok, Jobs.Job.t(), Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def retry_historical_data_workflow_job(job_id, event_id, attrs, opts \\ [])
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    event_opts =
      attrs
      |> Map.take([:organization_id, :mission_id])
      |> Keyword.new()

    with %Storage.BackfillLifecycleEvent{} = source_event <-
           Storage.fetch_backfill_lifecycle_event(event_id, event_opts),
         :ok <- require_historical_data_workflow_event_retryable(source_event),
         {:ok, source_job} <- require_historical_data_workflow_retry_job(job_id, source_event),
         :ok <- require_historical_data_workflow_retry_policy(source_event, source_job),
         {:ok, retried_job} <- retry_historical_data_workflow_job(job_id),
         {:ok, retry_event} <-
           record_historical_data_workflow_retry_event(source_event, retried_job, attrs, opts) do
      {:ok, retried_job, retry_event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec retry_historical_data_workflow_group_failed_jobs(binary(), workflow_attrs(), keyword()) ::
          {:ok, historical_data_workflow_group_retry_summary()} | {:error, term()}
  def retry_historical_data_workflow_group_failed_jobs(request_group_id, attrs, opts \\ [])

  def retry_historical_data_workflow_group_failed_jobs(request_group_id, attrs, opts)
      when is_binary(request_group_id) and is_map(attrs) and is_list(opts) do
    with {:ok, request_group_id} <- normalize_request_group_id(request_group_id),
         {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id),
         {:ok, failed_events} <-
           historical_data_workflow_group_retry_events(
             mission_id,
             organization_id,
             request_group_id,
             opts
           ) do
      failed_events
      |> Enum.reduce(historical_data_workflow_group_retry_summary(), fn event, summary ->
        retry_historical_data_workflow_group_failed_event(event, summary, attrs, opts)
      end)
      |> then(&{:ok, &1})
    end
  end

  def retry_historical_data_workflow_group_failed_jobs(_request_group_id, _attrs, _opts),
    do: {:error, {:missing_field, :request_group_id}}

  @spec record_historical_data_workflow_missing_replacement_inspection(
          binary(),
          binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_historical_data_workflow_missing_replacement_inspection(
        request_group_id,
        replacement_run_id,
        attrs,
        opts \\ []
      )

  def record_historical_data_workflow_missing_replacement_inspection(
        request_group_id,
        replacement_run_id,
        attrs,
        opts
      )
      when is_binary(request_group_id) and is_binary(replacement_run_id) and is_map(attrs) and
             is_list(opts) do
    with {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id),
         {:ok, source_event} <-
           historical_data_workflow_missing_replacement_event(
             mission_id,
             organization_id,
             request_group_id,
             replacement_run_id
           ),
         :ok <- require_historical_data_workflow_missing_replacement_policy(source_event) do
      record_historical_data_workflow_missing_replacement_inspection_event(
        source_event,
        attrs,
        opts
      )
    end
  end

  def record_historical_data_workflow_missing_replacement_inspection(
        _request_group_id,
        _replacement_run_id,
        _attrs,
        _opts
      ),
      do: {:error, {:missing_field, :request_group_id}}

  @spec record_historical_data_workflow_stale_replacement_inspection(
          binary(),
          binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_historical_data_workflow_stale_replacement_inspection(
        job_id,
        event_id,
        attrs,
        opts \\ []
      )
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    event_opts =
      attrs
      |> Map.take([:organization_id, :mission_id])
      |> Keyword.new()

    with %Storage.BackfillLifecycleEvent{} = source_event <-
           Storage.fetch_backfill_lifecycle_event(event_id, event_opts),
         :ok <- require_historical_data_workflow_stale_replacement_event(source_event),
         {:ok, job} <-
           require_historical_data_workflow_stale_replacement_job(job_id, source_event),
         :ok <- require_historical_data_workflow_stale_replacement_policy(source_event, job),
         {:ok, inspection_event} <-
           record_historical_data_workflow_stale_replacement_inspection_event(
             source_event,
             job,
             attrs,
             opts
           ) do
      {:ok, inspection_event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec requeue_historical_data_workflow_stale_replacement_job(
          binary(),
          binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Jobs.Job.t(), Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def requeue_historical_data_workflow_stale_replacement_job(
        job_id,
        event_id,
        attrs,
        opts \\ []
      )
      when is_binary(job_id) and is_binary(event_id) and is_map(attrs) and is_list(opts) do
    event_opts =
      attrs
      |> Map.take([:organization_id, :mission_id])
      |> Keyword.new()

    with %Storage.BackfillLifecycleEvent{} = source_event <-
           Storage.fetch_backfill_lifecycle_event(event_id, event_opts),
         :ok <- require_historical_data_workflow_stale_replacement_event(source_event),
         {:ok, job} <-
           require_historical_data_workflow_stale_replacement_job(job_id, source_event),
         :ok <- require_historical_data_workflow_stale_replacement_policy(source_event, job),
         {:ok, requeued_job} <-
           Jobs.requeue_running_job(job.job_id, :dashboard_stale_replacement_requeued),
         {:ok, requeue_event} <-
           record_historical_data_workflow_stale_replacement_requeue_event(
             source_event,
             job,
             requeued_job,
             attrs,
             opts
           ) do
      {:ok, requeued_job, requeue_event}
    else
      nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp historical_data_workflow_group_failed_events(mission_id, organization_id, request_group_id) do
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

  defp historical_data_workflow_group_retry_events(
         mission_id,
         organization_id,
         request_group_id,
         opts
       ) do
    failed_events =
      historical_data_workflow_group_failed_events(
        mission_id,
        organization_id,
        request_group_id
      )
      |> filter_historical_data_workflow_group_retry_events(opts)

    with :ok <-
           require_historical_data_workflow_group_retry_policy(request_group_id, failed_events) do
      {:ok, failed_events}
    end
  end

  defp filter_historical_data_workflow_group_retry_events(failed_events, opts) do
    case retry_run_id_set(opts) do
      nil ->
        failed_events

      run_id_set ->
        Enum.filter(failed_events, &MapSet.member?(run_id_set, &1.backfill_run_id))
    end
  end

  defp retry_run_id_set(opts) when is_list(opts) do
    opts
    |> Keyword.get(:retry_run_ids)
    |> normalize_retry_run_ids()
    |> case do
      [] -> nil
      run_ids -> MapSet.new(run_ids)
    end
  end

  defp retry_run_id_set(_opts), do: nil

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

  defp require_historical_data_workflow_retry_job(job_id, source_event) do
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

  defp historical_data_workflow_missing_replacement_event(
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
      correction_lifecycle_event?(event) and
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

  defp require_historical_data_workflow_missing_replacement_policy(source_event) do
    case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, source_event.backfill_run_id) do
      {:error, :job_not_found} ->
        :ok

      {:ok, %Jobs.Job{} = job} ->
        {:error,
         {:historical_workflow_missing_replacement_inspection_blocked,
          source_event.backfill_run_id, {:job_exists, job.status}}}
    end
  end

  defp require_historical_data_workflow_stale_replacement_event(source_event) do
    if correction_lifecycle_event?(source_event) do
      :ok
    else
      {:error,
       {:historical_workflow_stale_replacement_inspection_blocked,
        source_event.backfill_lifecycle_event_id, :not_replacement_event}}
    end
  end

  defp require_historical_data_workflow_stale_replacement_job(job_id, source_event) do
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

  defp require_historical_data_workflow_stale_replacement_policy(source_event, %Jobs.Job{} = job) do
    cond do
      job.status != :running ->
        {:error,
         {:historical_workflow_stale_replacement_inspection_blocked,
          source_event.backfill_lifecycle_event_id, :job_not_running}}

      not stale_historical_data_workflow_job?(job) ->
        {:error,
         {:historical_workflow_stale_replacement_inspection_blocked,
          source_event.backfill_lifecycle_event_id, :job_not_stale}}

      true ->
        :ok
    end
  end

  defp stale_historical_data_workflow_job?(%Jobs.Job{started_at: %DateTime{} = started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second) >=
      @stale_historical_data_workflow_job_seconds
  end

  defp stale_historical_data_workflow_job?(_job), do: false

  defp fetch_historical_data_workflow_job_for_source_event(source_event, error_tag) do
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

  defp require_historical_data_workflow_source_event_job_match(
         source_event,
         %Jobs.Job{} = job,
         error_tag
       ) do
    case historical_data_workflow_event_job_id(source_event) do
      event_job_id
      when is_binary(event_job_id) and event_job_id != "" and event_job_id != job.job_id ->
        {:error, {error_tag, source_event.backfill_lifecycle_event_id, :job_id_mismatch}}

      _event_job_id ->
        :ok
    end
  end

  defp require_historical_data_workflow_retry_policy(source_event, %Jobs.Job{} = job) do
    decision =
      source_event
      |> historical_data_workflow_retry_policy_context(job)
      |> WorkflowPolicy.retry_job_action_policy()

    if decision.eligible? do
      :ok
    else
      {:error,
       {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
        decision.reason}}
    end
  end

  defp historical_data_workflow_retry_policy_context(source_event, %Jobs.Job{} = job) do
    %{
      event_id: source_event.backfill_lifecycle_event_id,
      job_id: job.job_id,
      job_status: Atom.to_string(job.status),
      retryable:
        if(historical_data_workflow_event_retryable?(source_event), do: "true", else: "false"),
      recovery_action: historical_data_workflow_event_recovery_action(source_event)
    }
  end

  defp require_historical_data_workflow_group_retry_policy(request_group_id, failed_events) do
    decision =
      %{
        request_group_id: request_group_id,
        request_group_retryable_failed:
          failed_events
          |> Enum.count(&historical_data_workflow_group_retry_candidate?/1)
          |> Integer.to_string()
      }
      |> WorkflowPolicy.retry_group_action_policy()

    if decision.eligible? do
      :ok
    else
      {:error, {:historical_workflow_group_retry_blocked, request_group_id, decision.reason}}
    end
  end

  defp historical_data_workflow_group_retry_candidate?(event) do
    historical_data_workflow_event_retryable?(event) and
      not historical_data_workflow_event_correction_request_blocked?(event)
  end

  defp retry_historical_data_workflow_group_failed_event(event, summary, attrs, opts) do
    cond do
      not historical_data_workflow_event_retryable?(event) or
          historical_data_workflow_event_correction_request_blocked?(event) ->
        summary
        |> increment_historical_data_workflow_group_retry_summary(:nonretryable)
        |> prepend_historical_data_workflow_group_retry_nonretryable_item(
          event,
          nonretryable_group_retry_reason(event)
        )

      not is_binary(event.backfill_run_id) or event.backfill_run_id == "" ->
        summary
        |> increment_historical_data_workflow_group_retry_summary(:skipped)
        |> prepend_historical_data_workflow_group_retry_skipped_item(event, nil, :missing_run_id)

      true ->
        retry_historical_data_workflow_group_failed_job(event, summary, attrs, opts)
    end
  end

  defp retry_historical_data_workflow_group_failed_job(event, summary, attrs, opts) do
    case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, event.backfill_run_id) do
      {:ok, %{status: :failed, job_id: job_id}} ->
        with {:ok, retried_job} <- retry_historical_data_workflow_job(job_id),
             {:ok, retry_event} <-
               record_historical_data_workflow_retry_event(event, retried_job, attrs, opts) do
          summary
          |> increment_historical_data_workflow_group_retry_summary(:retried)
          |> prepend_historical_data_workflow_group_retry_event(retry_event)
        else
          {:error, reason} ->
            summary
            |> increment_historical_data_workflow_group_retry_summary(:failed)
            |> prepend_historical_data_workflow_group_retry_error_item(event, job_id, reason)
        end

      {:ok, job} ->
        summary
        |> increment_historical_data_workflow_group_retry_summary(:skipped)
        |> prepend_historical_data_workflow_group_retry_skipped_item(
          event,
          job,
          :job_not_failed
        )

      {:error, _reason} ->
        summary
        |> increment_historical_data_workflow_group_retry_summary(:skipped)
        |> prepend_historical_data_workflow_group_retry_skipped_item(
          event,
          nil,
          :job_status_missing
        )
    end
  end

  defp retry_historical_data_workflow_job(job_id) do
    with {:ok, %{job_type: :telemetry_historical_data_workflow}} <- Jobs.fetch_job(job_id),
         {:ok, retried_job} <- Jobs.retry_failed_job(job_id) do
      {:ok, retried_job}
    else
      {:ok, %{job_type: job_type}} ->
        {:error, {:unexpected_job_type, job_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_historical_data_workflow_retry_event(source_event, retried_job, attrs, opts) do
    source_event
    |> historical_data_workflow_retry_attrs(retried_job, attrs)
    |> then(fn event_attrs ->
      record_historical_data_workflow_event(
        historical_data_workflow_event_workflow(source_event),
        :retried,
        event_attrs,
        opts
      )
    end)
  end

  defp record_historical_data_workflow_stale_replacement_inspection_event(
         source_event,
         job,
         attrs,
         opts
       ) do
    source_event
    |> historical_data_workflow_stale_replacement_inspection_attrs(job, attrs)
    |> Storage.record_backfill_lifecycle_event(
      Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
    )
  end

  defp record_historical_data_workflow_missing_replacement_inspection_event(
         source_event,
         attrs,
         opts
       ) do
    source_event
    |> historical_data_workflow_missing_replacement_inspection_attrs(attrs)
    |> Storage.record_backfill_lifecycle_event(
      Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
    )
  end

  defp record_historical_data_workflow_stale_replacement_requeue_event(
         source_event,
         job,
         requeued_job,
         attrs,
         opts
       ) do
    source_event
    |> historical_data_workflow_stale_replacement_requeue_attrs(job, requeued_job, attrs)
    |> Storage.record_backfill_lifecycle_event(
      Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
    )
  end

  defp historical_data_workflow_retry_attrs(source_event, retried_job, attrs) do
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
      payload: historical_data_workflow_retry_payload(source_event, retried_job)
    }
    |> compact_attrs()
  end

  defp historical_data_workflow_stale_replacement_inspection_attrs(source_event, job, attrs) do
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
      event_type: historical_data_workflow_stale_replacement_inspection_event_type(source_event),
      authority: :advisory,
      reason: "dashboard_historical_workflow_stale_replacement_inspected",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload:
        historical_data_workflow_stale_replacement_payload(
          source_event,
          job,
          "inspect_stale_replacement_job"
        )
    }
    |> compact_attrs()
  end

  defp historical_data_workflow_missing_replacement_inspection_attrs(source_event, attrs) do
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
      event_type:
        historical_data_workflow_missing_replacement_inspection_event_type(source_event),
      authority: :advisory,
      reason: "dashboard_historical_workflow_missing_replacement_inspected",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload:
        historical_data_workflow_missing_replacement_payload(
          source_event,
          "inspect_missing_replacement_job"
        )
    }
    |> compact_attrs()
  end

  defp historical_data_workflow_stale_replacement_requeue_attrs(
         source_event,
         job,
         requeued_job,
         attrs
       ) do
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
      event_type: historical_data_workflow_stale_replacement_requeue_event_type(source_event),
      authority: :authoritative,
      reason: "dashboard_historical_workflow_stale_replacement_requeued",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      payload:
        source_event
        |> historical_data_workflow_stale_replacement_payload(
          job,
          "requeue_stale_replacement_job"
        )
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

  defp historical_data_workflow_stale_replacement_inspection_event_type(source_event) do
    case historical_data_workflow_event_workflow(source_event) do
      :import -> :import_stale_replacement_inspected
      "import" -> :import_stale_replacement_inspected
      _workflow -> :backfill_stale_replacement_inspected
    end
  end

  defp historical_data_workflow_missing_replacement_inspection_event_type(source_event) do
    case historical_data_workflow_event_workflow(source_event) do
      :import -> :import_missing_replacement_inspected
      "import" -> :import_missing_replacement_inspected
      _workflow -> :backfill_missing_replacement_inspected
    end
  end

  defp historical_data_workflow_stale_replacement_requeue_event_type(source_event) do
    case historical_data_workflow_event_workflow(source_event) do
      :import -> :import_stale_replacement_requeued
      "import" -> :import_stale_replacement_requeued
      _workflow -> :backfill_stale_replacement_requeued
    end
  end

  defp historical_data_workflow_stale_replacement_payload(source_event, job, action) do
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
      "stale_replacement_action" => action,
      "stale_replacement_source_event_id" => source_event.backfill_lifecycle_event_id,
      "stale_replacement_source_event_type" => Atom.to_string(source_event.event_type),
      "stale_replacement_run_id" => source_event.backfill_run_id,
      "stale_replacement_job_id" => job.job_id,
      "stale_replacement_job_status" => Atom.to_string(job.status),
      "stale_replacement_job_started_at" => datetime_payload(job.started_at),
      "stale_replacement_job_age_seconds" => job_age_seconds(job),
      "stale_replacement_stale_after_seconds" => @stale_historical_data_workflow_job_seconds
    })
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp historical_data_workflow_missing_replacement_payload(source_event, action) do
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
      "missing_replacement_action" => action,
      "missing_replacement_source_event_id" => source_event.backfill_lifecycle_event_id,
      "missing_replacement_source_event_type" => Atom.to_string(source_event.event_type),
      "missing_replacement_run_id" => source_event.backfill_run_id,
      "missing_replacement_expected_job_type" => "telemetry_historical_data_workflow"
    })
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
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

  defp historical_data_workflow_retry_payload(source_event, retried_job) do
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

  defp historical_data_workflow_event_workflow(source_event) do
    case Map.get(source_event.payload, "workflow") do
      workflow when workflow in ["backfill", "import"] ->
        workflow

      _other ->
        workflow_from_historical_data_workflow_event_type(source_event.event_type)
    end
  end

  defp workflow_from_historical_data_workflow_event_type(event_type) do
    event_type
    |> Atom.to_string()
    |> case do
      "import_" <> _stage -> :import
      _event_type -> :backfill
    end
  end

  defp historical_data_workflow_event_retryable?(%{payload: payload}) when is_map(payload) do
    case first_nested_map_value(payload, [
           ["source", "failure", "retryable"],
           [:source, :failure, :retryable],
           ["failure", "retryable"]
         ]) do
      {:ok, retryable} -> retryable not in [false, "false"]
      :error -> true
    end
  end

  defp historical_data_workflow_event_retryable?(_event), do: true

  defp require_historical_data_workflow_event_retryable(source_event) do
    cond do
      historical_data_workflow_event_correction_request_blocked?(source_event) ->
        {:error,
         {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
          :correct_workflow_request}}

      historical_data_workflow_event_retryable?(source_event) ->
        :ok

      true ->
        {:error,
         {:historical_workflow_retry_blocked, source_event.backfill_lifecycle_event_id,
          :nonretryable_failure}}
    end
  end

  defp historical_data_workflow_event_correction_request_blocked?(event) do
    historical_data_workflow_event_recovery_action(event) == "correct_workflow_request" and
      not correction_lifecycle_event?(event)
  end

  defp historical_data_workflow_event_recovery_action(%{payload: payload}) when is_map(payload) do
    case first_nested_map_value(payload, [
           ["source", "failure", "recovery_action"],
           [:source, :failure, :recovery_action],
           ["failure", "recovery_action"],
           [:failure, :recovery_action],
           ["recovery_action"],
           [:recovery_action]
         ]) do
      {:ok, recovery_action} -> recovery_action
      :error -> nil
    end
  end

  defp historical_data_workflow_event_recovery_action(_event), do: nil

  defp first_nested_map_value(map, paths) when is_map(map) and is_list(paths) do
    Enum.find_value(paths, :error, fn path ->
      case nested_map_value(map, path) do
        {:ok, value} -> {:ok, value}
        :error -> nil
      end
    end)
  end

  defp nested_map_value(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, {:ok, map}, fn key, {:ok, acc} ->
      if is_map(acc) and Map.has_key?(acc, key) do
        {:cont, {:ok, Map.get(acc, key)}}
      else
        {:halt, :error}
      end
    end)
  end

  defp historical_data_workflow_group_retry_summary do
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

  defp increment_historical_data_workflow_group_retry_summary(summary, key) do
    Map.update!(summary, key, &(&1 + 1))
  end

  defp prepend_historical_data_workflow_group_retry_error_item(summary, event, job_id, reason) do
    item = %{
      run_id: event.backfill_run_id,
      event_id: event.backfill_lifecycle_event_id,
      job_id: job_id,
      reason: retry_error_reason(reason)
    }

    Map.update(summary, :retry_error_items, [item], &[item | &1])
  end

  defp prepend_historical_data_workflow_group_retry_nonretryable_item(summary, event, reason) do
    item =
      event
      |> historical_data_workflow_group_retry_item(nil, reason)
      |> Map.put(:recovery_action, historical_data_workflow_event_recovery_action(event))
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()

    Map.update(summary, :nonretryable_items, [item], &[item | &1])
  end

  defp prepend_historical_data_workflow_group_retry_skipped_item(summary, event, job, reason) do
    item = historical_data_workflow_group_retry_item(event, job, reason)
    Map.update(summary, :skipped_items, [item], &[item | &1])
  end

  defp historical_data_workflow_group_retry_item(event, job, reason) do
    %{
      run_id: event.backfill_run_id,
      event_id: event.backfill_lifecycle_event_id,
      job_id: job && job.job_id,
      job_status: job && retry_error_reason(job.status),
      reason: retry_error_reason(reason)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp nonretryable_group_retry_reason(event) do
    if historical_data_workflow_event_correction_request_blocked?(event) do
      :correction_required
    else
      :nonretryable_failure
    end
  end

  defp retry_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp retry_error_reason(reason) when is_binary(reason), do: reason
  defp retry_error_reason(reason), do: inspect(reason)

  defp prepend_historical_data_workflow_group_retry_event(summary, event) do
    %{summary | events: [event | Map.get(summary, :events, [])]}
  end

  defp record_historical_data_workflow_group_transition_event(
         requested_event,
         {:ok, events, jobs},
         workflow,
         stage,
         attrs,
         opts
       ) do
    event_attrs = historical_data_workflow_group_transition_attrs(requested_event, attrs)

    case record_historical_data_workflow_transition_event(
           workflow,
           stage,
           requested_event,
           event_attrs,
           opts
         ) do
      {:ok, event} ->
        job_attrs = put_compact_attr(event_attrs, :payload, event.payload)

        job_result =
          maybe_start_historical_data_workflow_group_transition_job(stage, workflow, job_attrs)

        {:cont, {:ok, [event | events], [job_result | jobs]}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp record_historical_data_workflow_transition_event(
         workflow,
         stage,
         requested_event,
         event_attrs,
         opts
       ) do
    if correction_lifecycle_event?(requested_event) do
      record_historical_data_workflow_correction_transition_event(
        workflow,
        stage,
        requested_event,
        event_attrs,
        opts
      )
    else
      record_historical_data_workflow_event(workflow, stage, event_attrs, opts)
    end
  end

  defp record_historical_data_workflow_correction_transition_event(
         workflow,
         stage,
         correction_event,
         attrs,
         opts
       ) do
    with :ok <-
           require_historical_data_workflow_correction_event(workflow, correction_event, attrs),
         :ok <-
           require_historical_data_workflow_correction_transition_policy(stage, correction_event) do
      correction_event
      |> historical_data_workflow_correction_transition_attrs(attrs)
      |> then(fn event_attrs ->
        record_historical_data_workflow_event(workflow, stage, event_attrs, opts)
      end)
    end
  end

  defp require_historical_data_workflow_correction_transition_policy(stage, correction_event) do
    decision =
      correction_event
      |> historical_data_workflow_stage_transition_policy_context()
      |> historical_data_workflow_stage_action_policy(stage)

    if decision.eligible? do
      :ok
    else
      {:error,
       {:historical_workflow_correction_transition_blocked,
        correction_event.backfill_lifecycle_event_id, decision.reason}}
    end
  end

  defp historical_data_workflow_group_transition_result({:ok, events, jobs}) do
    {:ok, Enum.reverse(events), Enum.reverse(jobs)}
  end

  defp historical_data_workflow_group_transition_result({:error, reason}), do: {:error, reason}

  defp historical_data_workflow_group_transition_attrs(event, attrs) do
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
    |> put_compact_attr(:payload, historical_data_workflow_group_transition_payload(event, attrs))
    |> compact_attrs()
  end

  defp historical_data_workflow_stage_transition_attrs(event, attrs) do
    attrs
    |> put_compact_attr(:backfill_run_id, event.backfill_run_id)
    |> put_compact_attr(:import_run_id, event.backfill_run_id)
    |> put_compact_attr(:realm, get_attr(attrs, :realm) || event.realm)
    |> put_compact_attr(:data_source_id, get_attr(attrs, :data_source_id) || event.data_source_id)
    |> put_compact_attr(:binding_id, get_attr(attrs, :binding_id) || event.binding_id)
    |> put_compact_attr(:observable_id, get_attr(attrs, :observable_id) || event.observable_id)
    |> put_compact_attr(:point_id, get_attr(attrs, :point_id) || event.point_id)
    |> put_compact_attr(:source_from, get_attr(attrs, :source_from) || event.source_from)
    |> put_compact_attr(:source_to, get_attr(attrs, :source_to) || event.source_to)
    |> put_compact_attr(:payload, historical_data_workflow_stage_transition_payload(event))
    |> compact_attrs()
  end

  defp historical_data_workflow_correction_transition_attrs(event, attrs) do
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
    |> put_compact_attr(
      :payload,
      historical_data_workflow_correction_transition_payload(event, attrs)
    )
    |> compact_attrs()
  end

  defp historical_data_workflow_group_transition_payload(event, attrs) do
    attrs_payload =
      attrs
      |> get_attr(:payload, %{})
      |> ensure_map()

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
      "dashboard_context",
      "comparison_review_origin"
    ])
    |> Map.put("group_transition_source", "dashboard_group_action")
    |> put_compact_attr(
      "group_transition_scope",
      Map.get(attrs_payload, "group_transition_scope")
    )
    |> Map.put_new("requested_event_id", event.backfill_lifecycle_event_id)
  end

  defp historical_data_workflow_stage_transition_payload(event) do
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
      "dashboard_context",
      "comparison_review_origin"
    ])
    |> Map.put("stage_transition_source", "dashboard_stage_action")
    |> Map.put("source_event_id", event.backfill_lifecycle_event_id)
    |> Map.put("source_event_type", Atom.to_string(event.event_type))
  end

  defp historical_data_workflow_correction_transition_payload(event, attrs) do
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

  defp maybe_start_historical_data_workflow_group_transition_job(:started, workflow, attrs) do
    WorkflowJobs.start(workflow, attrs)
  end

  defp maybe_start_historical_data_workflow_group_transition_job(_stage, _workflow, _attrs),
    do: {:ok, nil}

  @doc false
  @spec execute_enqueued_historical_data_workflow(binary()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def execute_enqueued_historical_data_workflow(workflow_run_id)
      when is_binary(workflow_run_id) do
    WorkflowJobs.execute(workflow_run_id)
  end

  @spec apply_observation_identity_decision(
          binary(),
          observation_identity_decision() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, ObservationIdentityState.t()} | {:error, term()}
  def apply_observation_identity_decision(observation_identity_id, decision, attrs, opts \\ [])
      when is_binary(observation_identity_id) and (is_atom(decision) or is_binary(decision)) and
             is_map(attrs) and is_list(opts) do
    ObservationIdentityDecisions.apply_decision(observation_identity_id, decision, attrs, opts)
  end

  @spec apply_observation_identity_decisions(
          [map()],
          observation_identity_decision() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, observation_identity_decision_batch_summary()} | {:error, term()}
  def apply_observation_identity_decisions(items, decision, attrs, opts \\ [])
      when is_list(items) and (is_atom(decision) or is_binary(decision)) and is_map(attrs) and
             is_list(opts) do
    ObservationIdentityDecisions.apply_decisions(items, decision, attrs, opts)
  end

  @spec record_late_data_policy_decision(
          late_data_policy_decision() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_late_data_policy_decision(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    LateDataPolicy.record(decision, attrs, opts)
  end

  @spec execute_late_data_policy(
          late_data_policy_decision() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, late_data_policy_execution_result()} | {:error, term()}
  def execute_late_data_policy(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    LateDataPolicy.execute(decision, attrs, opts)
  end

  @spec late_data_policy_execution_mode(workflow_attrs()) :: late_data_policy_execution_mode()
  def late_data_policy_execution_mode(attrs), do: LateDataPolicy.execution_mode(attrs)

  @spec late_data_policy_write_opts(late_data_policy_decision() | binary(), keyword()) ::
          {:ok, keyword()} | {:error, term()}
  def late_data_policy_write_opts(decision, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_list(opts) do
    LateDataPolicy.write_opts(decision, opts)
  end

  defp execute_sample_workflow(workflow, samples, attrs, opts) do
    with :ok <- require_samples(samples),
         {:ok, mission_id} <- single_mission_id(samples),
         {:ok, workflow_attrs} <- workflow_attrs(workflow, mission_id, samples, attrs),
         {:ok, write_opts} <- write_opts(attrs, opts) do
      Storage.execute_backfill_lifecycle_workflow(
        workflow,
        workflow_attrs,
        write_opts,
        fn operation_write_opts -> Storage.persist_samples(samples, operation_write_opts) end,
        workflow_opts(opts)
      )
    end
  end

  defp workflow_attrs(workflow, mission_id, samples, attrs) do
    attrs =
      attrs
      |> Map.put_new(:mission_id, mission_id)
      |> Map.put_new(:source_from, first_datetime(samples, :generation_time))
      |> Map.put_new(:source_to, last_datetime(samples, :generation_time))
      |> Map.put_new(:receipt_from, first_datetime(samples, :receipt_time))
      |> Map.put_new(:receipt_to, last_datetime(samples, :receipt_time))
      |> Map.put_new(:sample_count, length(samples))
      |> maybe_put_single_sample_value(:observable_id, samples, :point_id)
      |> maybe_put_single_sample_value(:point_id, samples, :point_id)
      |> maybe_put_single_sample_value(:spacecraft_id, samples, :spacecraft_id)

    with :ok <- require_run_id(workflow, attrs),
         :ok <- require_present(attrs, :organization_id),
         :ok <- require_present(attrs, :data_source_id),
         :ok <- require_present(attrs, :binding_id),
         :ok <- require_realm(attrs) do
      {:ok, attrs}
    end
  end

  defp write_opts(attrs, opts) do
    attrs
    |> Map.take([
      :organization_id,
      :realm,
      :data_source_id,
      :binding_id,
      :source_endpoint_id,
      :replay_run_id,
      :recorded_at,
      :metadata,
      :validity_state,
      :revision,
      :supersedes_observation_id,
      :record_current_values?,
      :dashboard_runtime_invalidation?,
      :dashboard_runtime_cache
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.new()
    |> Keyword.merge(Keyword.get(opts, :write_opts, []))
    |> then(&{:ok, &1})
  end

  defp workflow_opts(opts) do
    Keyword.take(opts, [
      :approval,
      :record_requested?,
      :runtime_cache,
      :dashboard_runtime_invalidation?
    ])
  end

  defp require_samples([]), do: {:error, :no_telemetry_samples}
  defp require_samples([%Sample{} | _rest]), do: :ok
  defp require_samples(_samples), do: {:error, :invalid_telemetry_samples}

  defp single_mission_id(samples) do
    samples
    |> Enum.map(& &1.mission_id)
    |> Enum.uniq()
    |> case do
      [mission_id] when is_binary(mission_id) and mission_id != "" -> {:ok, mission_id}
      [_mission_id] -> {:error, {:missing_field, :mission_id}}
      mission_ids -> {:error, {:mixed_mission_samples, mission_ids}}
    end
  end

  defp require_run_id(:backfill, attrs), do: require_present(attrs, :backfill_run_id)
  defp require_run_id(:import, attrs), do: require_present(attrs, :import_run_id)

  defp require_present(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> :ok
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp required_attr(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp require_realm(attrs) do
    if is_nil(get_attr(attrs, :realm)) do
      {:error, {:missing_field, :realm}}
    else
      :ok
    end
  end

  defp maybe_put_single_sample_value(attrs, target_field, samples, sample_field) do
    case single_sample_value(samples, sample_field) do
      nil -> attrs
      value -> Map.put_new(attrs, target_field, value)
    end
  end

  defp single_sample_value(samples, sample_field) do
    samples
    |> Enum.map(&Map.get(&1, sample_field))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [value] -> value
      _other -> nil
    end
  end

  defp first_datetime(samples, field) do
    samples
    |> sample_datetimes(field)
    |> case do
      [] -> nil
      datetimes -> Enum.min_by(datetimes, &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp last_datetime(samples, field) do
    samples
    |> sample_datetimes(field)
    |> case do
      [] -> nil
      datetimes -> Enum.max_by(datetimes, &DateTime.to_unix(&1, :microsecond))
    end
  end

  defp sample_datetimes(samples, field) do
    samples
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&match?(%DateTime{}, &1))
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp put_compact_attr(attrs, _key, value) when value in [nil, ""], do: attrs
  defp put_compact_attr(attrs, key, value) when is_map(attrs), do: Map.put(attrs, key, value)

  defp compact_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
