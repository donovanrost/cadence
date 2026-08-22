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
  alias Cadence.Telemetry.DataManagement.WorkflowCorrections
  alias Cadence.Telemetry.DataManagement.WorkflowEventEvidence
  alias Cadence.Telemetry.DataManagement.WorkflowEvents
  alias Cadence.Telemetry.DataManagement.WorkflowJobs
  alias Cadence.Telemetry.DataManagement.WorkflowPolicy
  alias Cadence.Telemetry.DataManagement.WorkflowReplacementRecovery
  alias Cadence.Telemetry.DataManagement.WorkflowRetries
  alias Cadence.Telemetry.HistoryStore
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
  @type persistence_policy :: %{
          required(:storage) => Storage.policy(),
          required(:history_store) => HistoryStore.policy()
        }
  @type observation_identity_decision_batch_summary :: %{
          decision: observation_identity_decision(),
          workflow_id: binary() | nil,
          requested: non_neg_integer(),
          applied: non_neg_integer(),
          failed: non_neg_integer(),
          results: [map()],
          errors: [map()]
        }

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
    WorkflowCorrections.record_request(workflow, attrs, correction, opts)
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
    WorkflowCorrections.record_transition(workflow, stage, correction_event_id, attrs, opts)
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
         {:ok, source_event} <- WorkflowEventEvidence.fetch(source_event_id, attrs),
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

  defp require_historical_data_workflow_transition_source(workflow, stage, source_event) do
    source_event
    |> WorkflowEventEvidence.workflow()
    |> WorkflowEvents.normalize_workflow()
    |> case do
      {:ok, source_workflow} when source_workflow != workflow ->
        {:error,
         {:invalid_historical_workflow_transition_source,
          source_event.backfill_lifecycle_event_id, :workflow_mismatch}}

      {:ok, _source_workflow} ->
        require_historical_data_workflow_transition_stage(stage, source_event)

      {:error, _reason} ->
        {:error,
         {:invalid_historical_workflow_transition_source,
          source_event.backfill_lifecycle_event_id, :workflow_mismatch}}
    end
  end

  defp require_historical_data_workflow_transition_stage(stage, source_event) do
    if Storage.BackfillLifecycleGroup.payload_value(source_event, :stage) == Atom.to_string(stage) do
      {:error,
       {:historical_workflow_stage_transition_blocked, source_event.backfill_lifecycle_event_id,
        "already_in_stage"}}
    else
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
    WorkflowRetries.retry_job(job_id, event_id, attrs, opts)
  end

  @spec retry_historical_data_workflow_group_failed_jobs(binary(), workflow_attrs(), keyword()) ::
          {:ok, historical_data_workflow_group_retry_summary()} | {:error, term()}
  def retry_historical_data_workflow_group_failed_jobs(request_group_id, attrs, opts \\ []),
    do: WorkflowRetries.retry_group(request_group_id, attrs, opts)

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
      ) do
    WorkflowReplacementRecovery.record_missing_inspection(
      request_group_id,
      replacement_run_id,
      attrs,
      opts
    )
  end

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
    WorkflowReplacementRecovery.record_stale_inspection(job_id, event_id, attrs, opts)
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
    WorkflowReplacementRecovery.requeue_stale_job(job_id, event_id, attrs, opts)
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
    if WorkflowEventEvidence.correction?(requested_event) do
      WorkflowCorrections.transition_event(
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
    WorkflowJobs.execute(workflow_run_id, configured_policy())
  end

  @doc false
  @spec execute_enqueued_historical_data_workflow(binary(), persistence_policy()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def execute_enqueued_historical_data_workflow(workflow_run_id, %{} = policy)
      when is_binary(workflow_run_id) do
    WorkflowJobs.execute(workflow_run_id, policy)
  end

  @doc false
  @spec policy(Storage.policy(), HistoryStore.policy()) :: persistence_policy()
  def policy(%{} = storage_policy, %{} = history_store_policy) do
    %{storage: storage_policy, history_store: history_store_policy}
  end

  @doc false
  @spec handler(persistence_policy()) :: (binary() ->
                                            {:ok, Storage.BackfillLifecycleEvent.t()}
                                            | {:error, term()})
  def handler(%{} = policy) do
    fn workflow_run_id -> execute_enqueued_historical_data_workflow(workflow_run_id, policy) end
  end

  @doc false
  @spec configured_policy() :: persistence_policy()
  def configured_policy do
    storage_policy = Storage.configured_policy()

    policy(
      storage_policy,
      HistoryStore.policy(Application.get_env(:cadence, :telemetry_history_store, []),
        storage_policy: storage_policy
      )
    )
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
    LateDataPolicy.execute(decision, attrs, opts, persistence_policy(opts))
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
    policy = persistence_policy(opts)

    with :ok <- require_samples(samples),
         {:ok, mission_id} <- single_mission_id(samples),
         {:ok, workflow_attrs} <- workflow_attrs(workflow, mission_id, samples, attrs),
         {:ok, write_opts} <- write_opts(attrs, opts) do
      Storage.execute_backfill_lifecycle_workflow(
        workflow,
        workflow_attrs,
        write_opts,
        fn operation_write_opts ->
          Storage.persist_samples(policy.storage, samples, operation_write_opts)
        end,
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

  defp persistence_policy(opts) do
    Keyword.get_lazy(opts, :persistence_policy, &configured_policy/0)
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
