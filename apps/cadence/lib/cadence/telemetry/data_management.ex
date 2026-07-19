defmodule Cadence.Telemetry.DataManagement do
  @moduledoc """
  Product-level telemetry data-management workflows.

  Storage owns observation persistence. This module owns workflow-shaped entry
  points such as backfill/import sample writes that should emit lifecycle events
  visible to dashboards.
  """

  alias Cadence.Jobs
  alias Cadence.Telemetry.DataManagement.WorkflowPolicy
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
  @type observation_identity_decision_batch_summary :: %{
          decision: observation_identity_decision(),
          workflow_id: binary() | nil,
          requested: non_neg_integer(),
          applied: non_neg_integer(),
          failed: non_neg_integer(),
          results: [map()],
          errors: [map()]
        }

  @observation_identity_decisions [
    :mark_canonical,
    :mark_conflict,
    :mark_superseded,
    :mark_advisory
  ]
  @historical_data_workflows [:backfill, :import]
  @historical_data_workflow_stages [
    :requested,
    :approved,
    :rejected,
    :started,
    :completed,
    :failed,
    :retried
  ]
  @late_data_policy_decisions [:accept, :reject]
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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow),
         {:ok, stage} <- normalize_historical_data_workflow_stage(stage),
         :ok <- require_historical_data_workflow_context(workflow, attrs) do
      Storage.record_backfill_lifecycle_workflow_event(
        workflow,
        stage,
        attrs,
        historical_data_workflow_event_opts(opts)
      )
    end
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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow) do
      {point_ids, request_group_id, attrs} =
        historical_data_workflow_request_context(attrs, point_ids)

      record_historical_data_workflow_request_items(
        workflow,
        attrs,
        point_ids,
        request_group_id,
        opts
      )
    end
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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow),
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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow),
         {:ok, stage} <- normalize_historical_data_workflow_stage(stage),
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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow),
         {:ok, stage} <- normalize_historical_data_workflow_stage(stage),
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
    |> normalize_historical_data_workflow()
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

  defp historical_data_workflow_request_context(attrs, point_ids) do
    point_ids = if point_ids == [], do: [nil], else: point_ids

    request_group_id =
      get_attr(attrs, :backfill_run_id) || Cadence.Ids.new("telemetry_backfill_run")

    attrs = Map.put(attrs, :backfill_run_id, request_group_id)

    {point_ids, request_group_id, attrs}
  end

  defp record_historical_data_workflow_request_items(
         workflow,
         attrs,
         point_ids,
         request_group_id,
         opts
       ) do
    item_count = length(point_ids)

    point_ids
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {point_id, item_index}, {:ok, events} ->
      record_historical_data_workflow_request_item(
        workflow,
        attrs,
        point_id,
        request_group_id,
        item_count,
        item_index,
        opts,
        events
      )
    end)
    |> historical_data_workflow_request_result()
  end

  defp record_historical_data_workflow_request_item(
         workflow,
         attrs,
         point_id,
         request_group_id,
         item_count,
         item_index,
         opts,
         events
       ) do
    item_attrs =
      attrs
      |> historical_data_workflow_request_item_attrs(
        point_id,
        request_group_id,
        item_count,
        item_index
      )
      |> compact_attrs()

    case record_historical_data_workflow_event(workflow, :requested, item_attrs, opts) do
      {:ok, event} -> {:cont, {:ok, [event | events]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp historical_data_workflow_request_result({:ok, events}), do: {:ok, Enum.reverse(events)}
  defp historical_data_workflow_request_result({:error, reason}), do: {:error, reason}

  defp historical_data_workflow_request_item_attrs(
         attrs,
         point_id,
         request_group_id,
         item_count,
         item_index
       ) do
    item_run_id =
      historical_data_workflow_request_item_run_id(request_group_id, item_count, item_index)

    request_mode = if item_count == 1, do: "single_point", else: "bulk_points"

    attrs
    |> Map.put(:backfill_run_id, item_run_id)
    |> Map.put(:import_run_id, item_run_id)
    |> maybe_put_request_point(point_id)
    |> Map.put(
      :payload,
      attrs
      |> get_attr(:payload, %{})
      |> ensure_map()
      |> Map.merge(%{
        "request_source" => "dashboard_direct_request",
        "request_mode" => request_mode,
        "request_group_id" => request_group_id,
        "request_item_index" => item_index,
        "request_item_count" => item_count,
        "request_item_run_id" => item_run_id
      })
    )
  end

  defp maybe_put_request_point(attrs, nil), do: attrs

  defp maybe_put_request_point(attrs, point_id) do
    attrs
    |> Map.put(:observable_id, point_id)
    |> Map.put(:point_id, point_id)
  end

  defp historical_data_workflow_request_item_run_id(request_group_id, 1, _item_index),
    do: request_group_id

  defp historical_data_workflow_request_item_run_id(request_group_id, _item_count, item_index),
    do: "#{request_group_id}-#{String.pad_leading(Integer.to_string(item_index), 3, "0")}"

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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow),
         {:ok, stage} <- normalize_historical_data_workflow_stage(stage),
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
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow),
         :ok <- require_historical_data_workflow_context(workflow, attrs) do
      run_id = historical_data_workflow_run_id(workflow, attrs)

      Jobs.enqueue(
        :telemetry_historical_data_workflow,
        get_attr(attrs, :mission_id),
        run_id,
        historical_data_workflow_job_payload(workflow, attrs)
      )
    end
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
    start_historical_data_workflow_job(workflow, attrs)
  end

  defp maybe_start_historical_data_workflow_group_transition_job(_stage, _workflow, _attrs),
    do: {:ok, nil}

  @doc false
  @spec execute_enqueued_historical_data_workflow(binary()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def execute_enqueued_historical_data_workflow(workflow_run_id)
      when is_binary(workflow_run_id) do
    with {:ok, %Jobs.Job{} = job} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, workflow_run_id),
         {:ok, workflow, attrs} <- historical_data_workflow_job_attrs(job.payload) do
      case execute_historical_data_workflow_job(job, workflow, attrs) do
        {:ok, event} ->
          {:ok, event}

        {:error, reason} ->
          _result = record_historical_data_workflow_failure(job, workflow, attrs, reason)
          {:error, reason}
      end
    end
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
    with {:ok, decision} <- normalize_observation_identity_decision(decision),
         :ok <- require_observation_identity_decision_context(attrs),
         {:ok, decision_opts} <- observation_identity_decision_opts(attrs, opts) do
      Storage.apply_observation_identity_decision(
        observation_identity_id,
        decision,
        decision_opts
      )
    end
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
    with {:ok, decision} <- normalize_observation_identity_decision(decision),
         :ok <- require_observation_identity_decision_context(attrs),
         :ok <- require_observation_identity_decision_items(items) do
      items
      |> apply_observation_identity_decision_items(decision, attrs, opts)
      |> then(&{:ok, &1})
    end
  end

  @spec record_late_data_policy_decision(
          late_data_policy_decision() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record_late_data_policy_decision(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    with {:ok, decision} <- normalize_late_data_policy_decision(decision),
         :ok <- require_late_data_policy_context(attrs),
         {:ok, event_attrs} <- late_data_policy_event_attrs(decision, attrs) do
      Storage.record_backfill_lifecycle_event(
        event_attrs,
        Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
      )
    end
  end

  @spec execute_late_data_policy(
          late_data_policy_decision() | binary(),
          workflow_attrs(),
          keyword()
        ) ::
          {:ok, late_data_policy_execution_result()} | {:error, term()}
  def execute_late_data_policy(decision, attrs, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_map(attrs) and is_list(opts) do
    with {:ok, decision} <- normalize_late_data_policy_decision(decision),
         :ok <- require_late_data_policy_context(attrs),
         {:ok, samples, diagnostics} <- historical_data_workflow_source_samples(attrs),
         :ok <- persist_late_data_policy_samples(decision, samples, attrs, opts),
         {:ok, event_attrs} <- late_data_policy_event_attrs(decision, attrs, samples, diagnostics),
         {:ok, event} <-
           Storage.record_backfill_lifecycle_event(
             event_attrs,
             Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache])
           ) do
      {:ok, %{event: event, sample_count: length(samples), diagnostics: diagnostics}}
    end
  end

  @spec late_data_policy_execution_mode(workflow_attrs()) :: late_data_policy_execution_mode()
  def late_data_policy_execution_mode(attrs) when is_map(attrs) do
    if Enum.all?(
         [
           get_attr(attrs, :point_id),
           get_attr(attrs, :source_from),
           get_attr(attrs, :source_to)
         ],
         &late_data_policy_present?/1
       ) do
      :sample_execution
    else
      :event_only
    end
  end

  def late_data_policy_execution_mode(_attrs), do: :event_only

  defp late_data_policy_present?(value), do: value not in [nil, ""]

  @spec late_data_policy_write_opts(late_data_policy_decision() | binary(), keyword()) ::
          {:ok, keyword()} | {:error, term()}
  def late_data_policy_write_opts(decision, opts \\ [])
      when (is_atom(decision) or is_binary(decision)) and is_list(opts) do
    with {:ok, decision} <- normalize_late_data_policy_decision(decision) do
      {:ok, merge_late_data_policy_write_opts(decision, opts)}
    end
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

  defp historical_data_workflow_event_opts(opts) do
    Keyword.take(opts, [:runtime_cache, :dashboard_runtime_invalidation?])
  end

  defp historical_data_workflow_job_payload(workflow, attrs) do
    %{
      "workflow" => Atom.to_string(workflow),
      "attrs" => attrs
    }
  end

  defp historical_data_workflow_job_attrs(%{"workflow" => workflow, "attrs" => attrs})
       when is_binary(workflow) and is_map(attrs) do
    with {:ok, workflow} <- normalize_historical_data_workflow(workflow) do
      {:ok, workflow, attrs}
    end
  end

  defp historical_data_workflow_job_attrs(payload),
    do: {:error, {:invalid_historical_data_workflow_job_payload, payload}}

  defp historical_data_workflow_run_id(:backfill, attrs), do: get_attr(attrs, :backfill_run_id)

  defp historical_data_workflow_run_id(:import, attrs),
    do: get_attr(attrs, :import_run_id) || get_attr(attrs, :backfill_run_id)

  defp execute_historical_data_workflow_job(%Jobs.Job{} = job, workflow, attrs) do
    with {:ok, samples, diagnostics} <- historical_data_workflow_source_samples(attrs),
         :ok <- persist_historical_data_workflow_samples(workflow, samples, attrs) do
      attrs =
        attrs
        |> put_attr("sample_count", length(samples))
        |> put_attr("reason", "historical_data_job_completed")
        |> put_attr(
          "payload",
          historical_data_workflow_job_payload(job, "completed", diagnostics, attrs)
        )

      record_historical_data_workflow_event(workflow, :completed, attrs,
        dashboard_runtime_invalidation?: true
      )
    end
  end

  defp historical_data_workflow_source_samples(attrs) do
    with {:ok, mission_id} <- required_attr(attrs, :mission_id),
         {:ok, point_id} <- historical_data_workflow_point_id(attrs),
         {:ok, history_opts} <- historical_data_workflow_history_opts(attrs),
         {:ok, %{samples: samples, diagnostics: diagnostics}} <-
           HistoryStore.sample_history_result(mission_id, point_id, history_opts) do
      {:ok, samples, source_diagnostics(attrs, point_id, history_opts, diagnostics)}
    end
  end

  defp historical_data_workflow_point_id(attrs) do
    case get_attr(attrs, :point_id) || get_attr(attrs, :observable_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, :point_id}}
    end
  end

  defp historical_data_workflow_history_opts(attrs) do
    with {:ok, from_observed_at} <- optional_datetime_attr(attrs, :source_from),
         {:ok, to_observed_at} <- optional_datetime_attr(attrs, :source_to),
         {:ok, from_receipt_time} <- optional_datetime_attr(attrs, :receipt_from),
         {:ok, to_receipt_time} <- optional_datetime_attr(attrs, :receipt_to) do
      [
        organization_id: get_attr(attrs, :organization_id),
        spacecraft_id: get_attr(attrs, :source_spacecraft_id) || get_attr(attrs, :spacecraft_id),
        realm: get_attr(attrs, :source_realm) || get_attr(attrs, :realm),
        replay_run_id: get_attr(attrs, :source_replay_run_id) || get_attr(attrs, :replay_run_id),
        data_source_id:
          get_attr(attrs, :source_data_source_id) || get_attr(attrs, :data_source_id),
        source_binding_id: get_attr(attrs, :source_binding_id) || get_attr(attrs, :binding_id),
        from_observed_at: from_observed_at,
        to_observed_at: to_observed_at,
        from_receipt_time: from_receipt_time,
        to_receipt_time: to_receipt_time,
        order: :asc,
        limit: historical_data_workflow_history_limit(attrs)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> then(&{:ok, &1})
    end
  end

  defp historical_data_workflow_history_limit(attrs) do
    case get_attr(attrs, :source_limit) || get_attr(attrs, :limit) do
      limit when is_integer(limit) and limit > 0 -> limit
      limit when is_binary(limit) -> parse_positive_integer(limit, 10_000)
      _other -> 10_000
    end
  end

  defp persist_historical_data_workflow_samples(_workflow, [], _attrs), do: :ok

  defp persist_historical_data_workflow_samples(workflow, samples, attrs) do
    with {:ok, write_opts} <- historical_data_workflow_write_opts(workflow, attrs) do
      Storage.persist_samples(samples, write_opts)
    end
  end

  defp persist_late_data_policy_samples(_decision, [], _attrs, _opts), do: :ok

  defp persist_late_data_policy_samples(decision, samples, attrs, opts) do
    with {:ok, write_opts} <- late_data_policy_sample_write_opts(decision, attrs, opts) do
      Storage.persist_samples(samples, write_opts)
    end
  end

  defp late_data_policy_sample_write_opts(decision, attrs, opts) do
    base_opts =
      [
        organization_id: get_attr(attrs, :organization_id),
        realm: get_attr(attrs, :realm),
        data_source_id: get_attr(attrs, :data_source_id),
        binding_id: get_attr(attrs, :binding_id),
        source_endpoint_id: get_attr(attrs, :source_endpoint_id),
        replay_run_id: get_attr(attrs, :replay_run_id),
        recorded_at: get_attr(attrs, :recorded_at),
        metadata: get_attr(attrs, :metadata, %{}),
        revision: get_attr(attrs, :revision),
        supersedes_observation_id: get_attr(attrs, :supersedes_observation_id),
        dashboard_runtime_invalidation?:
          Keyword.get(opts, :dashboard_runtime_invalidation?, true),
        dashboard_runtime_cache: Keyword.get(opts, :dashboard_runtime_cache),
        record_backfill_lifecycle_event?: false,
        backfill_run_id: get_attr(attrs, :backfill_run_id),
        reason: get_attr(attrs, :reason) || "late_data_policy_write",
        actor_id: get_attr(attrs, :actor_id),
        actor_kind: get_attr(attrs, :actor_kind)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    late_data_policy_write_opts(decision, base_opts)
  end

  defp historical_data_workflow_write_opts(workflow, attrs) do
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
      backfill_lifecycle_event_type: historical_data_workflow_completion_event_type(workflow),
      backfill_run_id: historical_data_workflow_run_id(workflow, attrs),
      import_run_id: get_attr(attrs, :import_run_id),
      authority: get_attr(attrs, :authority),
      reason: "historical_data_job_write",
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> then(&{:ok, &1})
  end

  defp historical_data_workflow_completion_event_type(:backfill), do: :backfill_completed
  defp historical_data_workflow_completion_event_type(:import), do: :import_completed

  defp record_historical_data_workflow_failure(%Jobs.Job{} = job, workflow, attrs, reason) do
    attrs =
      attrs
      |> put_attr("reason", "historical_data_job_failed")
      |> put_attr(
        "payload",
        historical_data_workflow_job_payload(
          job,
          "failed",
          source_failure_diagnostics(attrs, reason),
          attrs
        )
      )

    record_historical_data_workflow_event(workflow, :failed, attrs,
      dashboard_runtime_invalidation?: true
    )
  end

  defp historical_data_workflow_job_payload(%Jobs.Job{} = job, status, diagnostics, attrs) do
    attrs
    |> historical_data_workflow_job_context_payload()
    |> Map.merge(%{
      "job_id" => job.job_id,
      "job_type" => Atom.to_string(job.job_type),
      "workflow_job_status" => status,
      "source" => diagnostics
    })
  end

  defp historical_data_workflow_job_context_payload(attrs) do
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

  defp source_diagnostics(attrs, point_id, history_opts, diagnostics) do
    %{
      "point_id" => point_id,
      "source_window" => source_window_diagnostics(history_opts),
      "source_identity" => source_identity_diagnostics(attrs),
      "history_diagnostics" => diagnostics
    }
  end

  defp source_failure_diagnostics(attrs, reason) do
    %{
      "point_id" => get_attr(attrs, :point_id) || get_attr(attrs, :observable_id),
      "source_window" =>
        source_window_diagnostics(
          from_observed_at: get_attr(attrs, :source_from),
          to_observed_at: get_attr(attrs, :source_to),
          from_receipt_time: get_attr(attrs, :receipt_from),
          to_receipt_time: get_attr(attrs, :receipt_to)
        ),
      "source_identity" => source_identity_diagnostics(attrs),
      "source_limit" => get_attr(attrs, :source_limit) || get_attr(attrs, :limit),
      "failure" => failure_diagnostics(reason)
    }
  end

  defp source_window_diagnostics(history_opts) when is_list(history_opts) do
    %{
      "from_observed_at" => diagnostic_value_text(Keyword.get(history_opts, :from_observed_at)),
      "to_observed_at" => diagnostic_value_text(Keyword.get(history_opts, :to_observed_at)),
      "from_receipt_time" => diagnostic_value_text(Keyword.get(history_opts, :from_receipt_time)),
      "to_receipt_time" => diagnostic_value_text(Keyword.get(history_opts, :to_receipt_time))
    }
  end

  defp source_identity_diagnostics(attrs) do
    %{
      "organization_id" => get_attr(attrs, :organization_id),
      "mission_id" => get_attr(attrs, :mission_id),
      "realm" => get_attr(attrs, :source_realm) || get_attr(attrs, :realm),
      "data_source_id" =>
        get_attr(attrs, :source_data_source_id) || get_attr(attrs, :data_source_id),
      "source_binding_id" => get_attr(attrs, :source_binding_id) || get_attr(attrs, :binding_id)
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

  defp observation_identity_decision_opts(attrs, opts) do
    attrs
    |> Map.take([
      :organization_id,
      :mission_id,
      :realm,
      :data_source_id,
      :binding_id,
      :canonical_observation_id,
      :canonical_sample_id,
      :canonical_revision,
      :decision_reason,
      :reason,
      :decided_at,
      :operator_id,
      :actor_id,
      :actor_kind
    ])
    |> Map.put(:evidence_ref, observation_identity_decision_evidence_ref(attrs))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.new()
    |> Keyword.merge(Keyword.take(opts, [:dashboard_runtime_invalidation?, :runtime_cache]))
    |> Keyword.merge(Keyword.get(opts, :decision_opts, []))
    |> then(&{:ok, &1})
  end

  defp require_observation_identity_decision_items([]),
    do: {:error, :empty_observation_identity_decision_batch}

  defp require_observation_identity_decision_items(_items), do: :ok

  defp apply_observation_identity_decision_items(items, decision, attrs, opts) do
    item_count = length(items)

    items
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {item, item_index}, acc ->
      apply_observation_identity_decision_item(
        item,
        item_index,
        item_count,
        decision,
        attrs,
        opts
      )
      |> collect_observation_identity_decision_item(acc)
    end)
    |> observation_identity_decision_batch_summary(decision, attrs, item_count)
  end

  defp collect_observation_identity_decision_item({:ok, result}, {results, errors}) do
    {[result | results], errors}
  end

  defp collect_observation_identity_decision_item({:error, error}, {results, errors}) do
    {results, [error | errors]}
  end

  defp apply_observation_identity_decision_item(
         item,
         item_index,
         item_count,
         decision,
         attrs,
         opts
       )
       when is_map(item) do
    observation_identity_id = get_attr(item, :observation_identity_id)

    if is_binary(observation_identity_id) and String.trim(observation_identity_id) != "" do
      item_attrs =
        attrs
        |> Map.merge(observation_identity_decision_item_attrs(item))
        |> Map.put(:observation_identity_id, observation_identity_id)
        |> put_compact_attr(:decision_item_index, item_index)
        |> put_compact_attr(:decision_item_count, item_count)
        |> put_compact_attr(
          :evidence_ref,
          observation_identity_decision_item_evidence(item, attrs, item_index, item_count)
        )

      case apply_observation_identity_decision(
             observation_identity_id,
             decision,
             item_attrs,
             opts
           ) do
        {:ok, state} ->
          {:ok,
           %{
             index: item_index,
             observation_identity_id: observation_identity_id,
             validity_state: state.validity_state,
             canonical_observation_id: state.canonical_observation_id,
             canonical_sample_id: state.canonical_sample_id,
             canonical_revision: state.canonical_revision
           }}

        {:error, reason} ->
          {:error,
           %{
             index: item_index,
             observation_identity_id: observation_identity_id,
             reason: reason
           }}
      end
    else
      {:error,
       %{
         index: item_index,
         observation_identity_id: nil,
         reason: {:missing_field, :observation_identity_id}
       }}
    end
  end

  defp apply_observation_identity_decision_item(
         item,
         item_index,
         _item_count,
         _decision,
         _attrs,
         _opts
       ) do
    {:error,
     %{
       index: item_index,
       observation_identity_id: nil,
       reason: {:invalid_observation_identity_decision_item, item}
     }}
  end

  defp observation_identity_decision_item_attrs(item) do
    %{}
    |> put_compact_attr(:canonical_observation_id, get_attr(item, :canonical_observation_id))
    |> put_compact_attr(:canonical_sample_id, get_attr(item, :canonical_sample_id))
    |> put_compact_attr(:canonical_revision, get_attr(item, :canonical_revision))
    |> put_compact_attr(:decision_reason, get_attr(item, :decision_reason))
  end

  defp observation_identity_decision_item_evidence(item, attrs, item_index, item_count) do
    attrs
    |> get_attr(:evidence_ref, %{})
    |> ensure_map()
    |> Map.merge(ensure_map(get_attr(item, :evidence_ref, %{})))
    |> Map.put(
      "bulk_workflow_item",
      %{
        "kind" => "telemetry_correction_authority_workflow_item",
        "workflow_id" =>
          get_attr(attrs, :correction_workflow_id) ||
            get_attr(attrs, :workflow_id) ||
            get_attr(attrs, :decision_workflow_id),
        "item_index" => item_index,
        "item_count" => item_count,
        "observation_identity_id" => get_attr(item, :observation_identity_id),
        "selection_kind" => get_attr(attrs, :selection_kind)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()
    )
  end

  defp observation_identity_decision_batch_summary({results, errors}, decision, attrs, item_count) do
    results = Enum.reverse(results)
    errors = Enum.reverse(errors)

    %{
      decision: decision,
      workflow_id:
        get_attr(attrs, :correction_workflow_id) ||
          get_attr(attrs, :workflow_id) ||
          get_attr(attrs, :decision_workflow_id),
      requested: item_count,
      applied: length(results),
      failed: length(errors),
      results: results,
      errors: errors
    }
  end

  defp late_data_policy_event_attrs(decision, attrs) do
    late_data_policy_event_attrs(decision, attrs, nil, nil)
  end

  defp late_data_policy_event_attrs(decision, attrs, samples, diagnostics) do
    with {:ok, source_from} <- optional_datetime_attr(attrs, :source_from),
         {:ok, source_to} <- optional_datetime_attr(attrs, :source_to),
         {:ok, receipt_from} <- optional_datetime_attr(attrs, :receipt_from),
         {:ok, receipt_to} <- optional_datetime_attr(attrs, :receipt_to) do
      attrs =
        attrs
        |> late_data_policy_base_attrs()
        |> Map.merge(%{
          event_type: late_data_policy_event_type(decision),
          authority: late_data_policy_authority(decision, attrs),
          reason: late_data_policy_reason(decision, attrs),
          source_from: source_from,
          source_to: source_to,
          receipt_from: receipt_from,
          receipt_to: receipt_to,
          sample_count: late_data_policy_sample_count(attrs, samples),
          payload: late_data_policy_payload(decision, attrs, samples, diagnostics)
        })
        |> compact_attrs()

      {:ok, attrs}
    end
  end

  defp late_data_policy_base_attrs(attrs) do
    %{
      backfill_run_id: get_attr(attrs, :backfill_run_id),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      realm: get_attr(attrs, :realm),
      data_source_id: get_attr(attrs, :data_source_id),
      binding_id: get_attr(attrs, :binding_id),
      observable_id: get_attr(attrs, :observable_id),
      point_id: get_attr(attrs, :point_id),
      spacecraft_id: get_attr(attrs, :spacecraft_id),
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind)
    }
  end

  defp late_data_policy_event_type(:accept), do: :late_data_accepted
  defp late_data_policy_event_type(:reject), do: :late_data_rejected

  defp late_data_policy_authority(:accept, attrs) do
    get_attr(attrs, :authority) || :authoritative
  end

  defp late_data_policy_authority(:reject, attrs) do
    get_attr(attrs, :authority) || :advisory
  end

  defp late_data_policy_reason(decision, attrs) do
    get_attr(attrs, :reason) || "dashboard_late_data_#{decision}"
  end

  defp late_data_policy_sample_count(_attrs, samples) when is_list(samples), do: length(samples)

  defp late_data_policy_sample_count(attrs, _samples) do
    case get_attr(attrs, :sample_count) do
      count when is_integer(count) and count >= 0 -> count
      count when is_binary(count) -> parse_non_negative_integer(count)
      _count -> nil
    end
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _invalid -> nil
    end
  end

  defp late_data_policy_payload(decision, attrs, samples, diagnostics) do
    execution_mode = late_data_policy_payload_execution_mode(attrs, samples)

    attrs
    |> get_attr(:payload, %{})
    |> ensure_map()
    |> Map.merge(%{
      "kind" => "late_data_policy_decision",
      "policy_decision" => Atom.to_string(decision),
      "execution_mode" => Atom.to_string(execution_mode),
      "write_validity_state" => decision |> late_data_policy_validity_state() |> Atom.to_string(),
      "record_current_values" =>
        late_data_policy_record_current_values?(decision, execution_mode),
      "refresh_latest_value" => late_data_policy_refresh_latest_value?(decision, execution_mode),
      "projection_effect" => late_data_policy_projection_effect(decision, execution_mode),
      "source_event_id" => get_attr(attrs, :source_event_id),
      "source_event_type" => get_attr(attrs, :source_event_type),
      "requested_by" => get_attr(attrs, :requested_by) || "dashboard_data_link_inspector",
      "selected_sample_count" => selected_sample_count(samples),
      "source" => diagnostics
    })
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp selected_sample_count(samples) when is_list(samples), do: length(samples)
  defp selected_sample_count(_samples), do: nil

  defp late_data_policy_payload_execution_mode(attrs, samples) do
    case get_attr(attrs, :execution_mode) do
      mode when mode in [:sample_execution, "sample_execution"] -> :sample_execution
      mode when mode in [:event_only, "event_only"] -> :event_only
      _mode when is_list(samples) -> :sample_execution
      _mode -> :event_only
    end
  end

  defp merge_late_data_policy_write_opts(decision, opts) do
    opts
    |> Keyword.merge(late_data_policy_locked_write_opts(decision))
    |> Keyword.update(
      :metadata,
      late_data_policy_metadata(decision),
      &Map.merge(ensure_map(&1), late_data_policy_metadata(decision))
    )
  end

  defp late_data_policy_locked_write_opts(decision) do
    [
      late_data?: true,
      backfill_lifecycle_event_type: late_data_policy_event_type(decision),
      validity_state: late_data_policy_validity_state(decision),
      record_current_values?: late_data_policy_record_current_values?(decision),
      refresh_latest_value?: late_data_policy_refresh_latest_value?(decision),
      authority: late_data_policy_authority(decision, %{})
    ]
  end

  defp late_data_policy_metadata(decision) do
    %{
      "late_data_policy_decision" => Atom.to_string(decision),
      "late_data_projection_effect" => late_data_policy_projection_effect(decision)
    }
  end

  defp late_data_policy_validity_state(:accept), do: :canonical
  defp late_data_policy_validity_state(:reject), do: :advisory

  defp late_data_policy_record_current_values?(decision),
    do: late_data_policy_record_current_values?(decision, :sample_execution)

  defp late_data_policy_record_current_values?(:accept, :sample_execution), do: true
  defp late_data_policy_record_current_values?(_decision, _execution_mode), do: false

  defp late_data_policy_refresh_latest_value?(decision),
    do: late_data_policy_refresh_latest_value?(decision, :sample_execution)

  defp late_data_policy_refresh_latest_value?(:accept, :sample_execution), do: true
  defp late_data_policy_refresh_latest_value?(_decision, _execution_mode), do: false

  defp late_data_policy_projection_effect(decision),
    do: late_data_policy_projection_effect(decision, :sample_execution)

  defp late_data_policy_projection_effect(_decision, :event_only), do: "audit_event_only"

  defp late_data_policy_projection_effect(:accept, :sample_execution),
    do: "canonical_history_and_current_projection"

  defp late_data_policy_projection_effect(:reject, :sample_execution), do: "advisory_history_only"

  defp observation_identity_decision_evidence_ref(attrs) do
    evidence_ref = ensure_map(get_attr(attrs, :evidence_ref, %{}))

    attrs
    |> correction_workflow_evidence()
    |> case do
      workflow_evidence when workflow_evidence == %{} ->
        evidence_ref

      workflow_evidence when evidence_ref == %{} ->
        workflow_evidence

      workflow_evidence ->
        Map.put(evidence_ref, "correction_workflow", workflow_evidence)
    end
  end

  defp correction_workflow_evidence(attrs) do
    workflow_id =
      get_attr(attrs, :correction_workflow_id) ||
        get_attr(attrs, :workflow_id) ||
        get_attr(attrs, :decision_workflow_id)

    %{
      "kind" => "telemetry_correction_authority_workflow",
      "id" => workflow_id,
      "authority" => get_attr(attrs, :authority),
      "requested_by" => get_attr(attrs, :requested_by),
      "operator_id" => get_attr(attrs, :operator_id) || get_attr(attrs, :actor_id),
      "reason" => get_attr(attrs, :decision_reason) || get_attr(attrs, :reason),
      "item_index" => get_attr(attrs, :decision_item_index),
      "item_count" => get_attr(attrs, :decision_item_count),
      "item_observation_identity_id" => get_attr(attrs, :observation_identity_id),
      "selection_kind" => get_attr(attrs, :selection_kind)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp normalize_observation_identity_decision(decision)
       when decision in @observation_identity_decisions,
       do: {:ok, decision}

  defp normalize_observation_identity_decision(decision) when is_binary(decision) do
    normalized =
      decision
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    case Enum.find(@observation_identity_decisions, &(Atom.to_string(&1) == normalized)) do
      nil -> {:error, {:unsupported_observation_identity_decision, decision}}
      decision -> {:ok, decision}
    end
  end

  defp normalize_observation_identity_decision(decision),
    do: {:error, {:unsupported_observation_identity_decision, decision}}

  defp normalize_late_data_policy_decision(decision)
       when decision in @late_data_policy_decisions,
       do: {:ok, decision}

  defp normalize_late_data_policy_decision(decision) when is_binary(decision) do
    decision
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> case do
      value when value in ["accept", "accepted", "late_data_accepted"] -> {:ok, :accept}
      value when value in ["reject", "rejected", "late_data_rejected"] -> {:ok, :reject}
      _unsupported -> {:error, {:unsupported_late_data_policy_decision, decision}}
    end
  end

  defp normalize_late_data_policy_decision(decision),
    do: {:error, {:unsupported_late_data_policy_decision, decision}}

  defp normalize_historical_data_workflow(workflow)
       when workflow in @historical_data_workflows,
       do: {:ok, workflow}

  defp normalize_historical_data_workflow(workflow) when is_binary(workflow) do
    normalize_enum(
      workflow,
      @historical_data_workflows,
      :unsupported_historical_data_workflow
    )
  end

  defp normalize_historical_data_workflow(workflow),
    do: {:error, {:unsupported_historical_data_workflow, workflow}}

  defp normalize_historical_data_workflow_stage(stage)
       when stage in @historical_data_workflow_stages,
       do: {:ok, stage}

  defp normalize_historical_data_workflow_stage(stage) when is_binary(stage) do
    normalize_enum(
      stage,
      @historical_data_workflow_stages,
      :unsupported_historical_data_workflow_stage
    )
  end

  defp normalize_historical_data_workflow_stage(stage),
    do: {:error, {:unsupported_historical_data_workflow_stage, stage}}

  defp normalize_enum(value, allowed, error) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    case Enum.find(allowed, &(Atom.to_string(&1) == normalized)) do
      nil -> {:error, {error, value}}
      atom -> {:ok, atom}
    end
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

  defp require_observation_identity_decision_context(attrs) do
    [:organization_id, :mission_id, :data_source_id, :binding_id]
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case require_present(attrs, field) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> require_realm(attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_late_data_policy_context(attrs) do
    [:organization_id, :mission_id, :backfill_run_id, :data_source_id, :binding_id]
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case require_present(attrs, field) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> require_realm(attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_historical_data_workflow_context(workflow, attrs) do
    [:organization_id, :mission_id, :data_source_id, :binding_id]
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case require_present(attrs, field) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> require_historical_data_workflow_realm_and_run_id(workflow, attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_historical_data_workflow_realm_and_run_id(workflow, attrs) do
    case require_realm(attrs) do
      :ok -> require_run_id(workflow, attrs)
      {:error, reason} -> {:error, reason}
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

  defp optional_datetime_attr(attrs, field) do
    case get_attr(attrs, field) do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      %DateTime{} = datetime ->
        {:ok, datetime}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, reason} -> {:error, {:invalid_datetime_field, field, value, reason}}
        end

      value ->
        {:error, {:invalid_datetime_field, field, value}}
    end
  end

  defp parse_positive_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp diagnostic_value_text(nil), do: nil
  defp diagnostic_value_text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp diagnostic_value_text(value) when is_binary(value), do: value
  defp diagnostic_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp diagnostic_value_text(value) when is_integer(value), do: Integer.to_string(value)
  defp diagnostic_value_text(value), do: inspect(value)

  defp put_attr(attrs, key, value) when is_map(attrs) and is_binary(key) do
    Map.put(attrs, key, value)
  end

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
