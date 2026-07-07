defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlsPresentation do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcomePresentation,
    HistoricalWorkflowActionPolicy,
    HistoricalWorkflowActionPolicyAction,
    HistoricalWorkflowBlockedActionExplanation
  }

  @type action :: HistoricalWorkflowActionPolicyAction.t()
  @type action_outcome :: HistoricalWorkflowActionOutcomePresentation.t()
  @type blocked_explanation :: HistoricalWorkflowBlockedActionExplanation.t()

  @type t :: %__MODULE__{
          controls_available: boolean(),
          form_params: map(),
          correction_form_params: map(),
          latest_action_outcome: action_outcome() | nil,
          blocked_action_explanations: [blocked_explanation()],
          group_actions: boolean(),
          group_summary: boolean(),
          group_retry_action: action(),
          group_retryable_failures: boolean(),
          job_status: boolean(),
          job_status_class: String.t(),
          job_retry_action: action(),
          job_retryable: boolean(),
          correction_request_action: action(),
          correction_requestable: boolean(),
          stage_actions: [action()],
          group_stage_actions: [action()]
        }

  defstruct [
    :form_params,
    :correction_form_params,
    :latest_action_outcome,
    :job_status_class,
    controls_available: false,
    blocked_action_explanations: [],
    group_actions: false,
    group_summary: false,
    group_retry_action: %HistoricalWorkflowActionPolicyAction{},
    group_retryable_failures: false,
    job_status: false,
    job_retry_action: %HistoricalWorkflowActionPolicyAction{},
    job_retryable: false,
    correction_request_action: %HistoricalWorkflowActionPolicyAction{},
    correction_requestable: false,
    stage_actions: [],
    group_stage_actions: []
  ]

  def build(context, action_outcome \\ nil)

  def build(context, action_outcome) when is_map(context) do
    actions = HistoricalWorkflowActionPolicy.build(context)
    stage_actions = stage_actions(context)
    group_stage_actions = group_stage_actions(context)
    group_actions? = group_actions?(context)
    group_summary? = group_summary?(context)
    job_status? = job_status?(context)

    %__MODULE__{
      controls_available: controls_available?(context),
      form_params: form_params(context),
      correction_form_params: correction_form_params(context),
      latest_action_outcome: action_outcome_presentation(context, action_outcome),
      blocked_action_explanations:
        blocked_action_explanations(%{
          stage_actions: stage_actions,
          group_stage_actions: group_stage_actions,
          group_actions?: group_actions?,
          group_summary?: group_summary?,
          job_status?: job_status?,
          retry_job: actions.retry_job,
          retry_group_failed_jobs: actions.retry_group_failed_jobs,
          correction_request: actions.correction_request
        }),
      group_actions: group_actions?,
      group_summary: group_summary?,
      group_retry_action: actions.retry_group_failed_jobs,
      group_retryable_failures: actions.retry_group_failed_jobs.eligible?,
      job_status: job_status?,
      job_status_class: job_status_class(Map.get(context, :job_status)),
      job_retry_action: actions.retry_job,
      job_retryable: actions.retry_job.eligible?,
      correction_request_action: actions.correction_request,
      correction_requestable: actions.correction_request.eligible?,
      stage_actions: stage_actions,
      group_stage_actions: group_stage_actions
    }
  end

  def build(_context, action_outcome), do: build(%{}, action_outcome)

  def controls_available?(context) when is_map(context) do
    Enum.all?(
      [
        Map.get(context, :workflow),
        Map.get(context, :run_id),
        Map.get(context, :realm),
        Map.get(context, :data_source_id),
        Map.get(context, :source_binding_id)
      ],
      &present_text?/1
    )
  end

  def controls_available?(_context), do: false

  def form_params(context) when is_map(context) do
    [
      {"workflow", :workflow},
      {"run_id", :run_id},
      {"realm", :realm},
      {"data_source_id", :data_source_id},
      {"source_binding_id", :source_binding_id},
      {"observable_id", :observable_id},
      {"point_id", :point_id},
      {"dashboard_id", :dashboard_id},
      {"dashboard_version", :dashboard_version},
      {"dashboard_time_mode", :dashboard_time_mode},
      {"dashboard_replay_run_id", :dashboard_replay_run_id},
      {"dashboard_data_view", :dashboard_data_view},
      {"dashboard_limit_mode", :dashboard_limit_mode},
      {"request_group_id", :request_group_id},
      {"request_mode", :request_mode},
      {"source_from", :source_from},
      {"source_to", :source_to}
    ]
    |> Map.new(fn {form_key, context_key} -> {form_key, Map.get(context, context_key) || ""} end)
    |> Map.merge(%{"stage" => "", "reason" => "", "confirmed" => ""})
  end

  def correction_form_params(context) when is_map(context) do
    %{
      "workflow" => context_value(context, [:workflow]),
      "run_id" => corrected_run_id(context),
      "original_run_id" => context_value(context, [:run_id]),
      "original_event_id" => context_value(context, [:event_id]),
      "original_job_id" => context_value(context, [:job_id]),
      "realm" => context_value(context, [:source_realm, :realm]),
      "data_source_id" => context_value(context, [:source_data_source_id, :data_source_id]),
      "source_binding_id" =>
        context_value(context, [:source_binding_id_override, :source_binding_id]),
      "observable_id" => context_value(context, [:observable_id, :source_point_id]),
      "point_id" => context_value(context, [:source_point_id, :point_id]),
      "dashboard_id" => context_value(context, [:dashboard_id]),
      "dashboard_version" => context_value(context, [:dashboard_version]),
      "dashboard_time_mode" => context_value(context, [:dashboard_time_mode]),
      "dashboard_replay_run_id" => context_value(context, [:dashboard_replay_run_id]),
      "dashboard_data_view" => context_value(context, [:dashboard_data_view]),
      "dashboard_limit_mode" => context_value(context, [:dashboard_limit_mode]),
      "request_mode" => context_value(context, [:request_mode]),
      "request_group_id" => context_value(context, [:request_group_id]),
      "request_item_index" => request_item_index(context),
      "request_item_count" => request_item_count(context),
      "request_item_run_id" => corrected_run_id(context),
      "source_from" => context_value(context, [:source_from_override, :source_from]),
      "source_to" => context_value(context, [:source_to_override, :source_to]),
      "reason" => "corrected_historical_data_workflow_request",
      "confirmed" => ""
    }
  end

  defp action_outcome_presentation(_context, nil), do: nil

  defp action_outcome_presentation(context, outcome) when is_map(context) and is_map(outcome) do
    action = text_value(Map.get(outcome, :action))
    status = text_value(Map.get(outcome, :status)) || "unknown"
    message = text_value(Map.get(outcome, :message))

    if present_text?(action) and present_text?(message) and
         action_outcome_applies?(context, outcome) do
      %{
        action: action,
        action_label: action_label(action),
        status: status,
        status_label: status_label(status),
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
        retry_run_ids: text_value(Map.get(outcome, :retry_run_ids)),
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
        dashboard_context: Map.get(outcome, :dashboard_context),
        message: message,
        class: action_outcome_class(status),
        badge_class: action_outcome_badge_class(status)
      }
      |> HistoricalWorkflowActionOutcomePresentation.normalize()
    end
  end

  defp action_outcome_presentation(_context, _outcome), do: nil

  defp action_outcome_applies?(context, outcome) do
    event_matches? =
      scoped_value_matches?(
        text_value(Map.get(outcome, :target_event_id)),
        text_value(Map.get(context, :event_id))
      )

    run_matches? =
      scoped_value_matches?(
        text_value(Map.get(outcome, :target_run_id)),
        text_value(Map.get(context, :run_id))
      )

    event_matches? and run_matches?
  end

  defp scoped_value_matches?(nil, _context_value), do: true
  defp scoped_value_matches?("", _context_value), do: true
  defp scoped_value_matches?(_scoped_value, nil), do: false
  defp scoped_value_matches?(_scoped_value, ""), do: false
  defp scoped_value_matches?(scoped_value, context_value), do: scoped_value == context_value

  defp blocked_action_explanations(%{
         stage_actions: stage_actions,
         group_stage_actions: group_stage_actions,
         group_actions?: group_actions?,
         group_summary?: group_summary?,
         job_status?: job_status?,
         retry_job: retry_job,
         retry_group_failed_jobs: retry_group_failed_jobs,
         correction_request: correction_request
       }) do
    actions =
      stage_actions ++
        maybe_actions(group_actions?, group_stage_actions) ++
        maybe_actions(group_summary?, [retry_group_failed_jobs]) ++
        maybe_actions(job_status?, [retry_job, correction_request])

    actions
    |> Enum.reject(&Map.get(&1, :eligible?))
    |> Enum.map(&action_explanation/1)
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_actions(true, actions), do: actions
  defp maybe_actions(_condition, _actions), do: []

  defp action_explanation(action) when is_map(action) do
    explanation = text_value(Map.get(action, :explanation))

    if present_text?(explanation) do
      %{
        id: text_value(Map.get(action, :id)),
        kind: text_value(Map.get(action, :kind)),
        label: text_value(Map.get(action, :label)),
        reason: text_value(Map.get(action, :reason)),
        explanation: explanation,
        state_summary: text_value(Map.get(action, :state_summary)),
        available_when: text_value(Map.get(action, :available_when))
      }
      |> HistoricalWorkflowBlockedActionExplanation.normalize()
    end
  end

  defp action_explanation(_action), do: nil

  defp group_actions?(context) when is_map(context) do
    present_text?(Map.get(context, :request_group_id)) and
      Map.get(context, :request_mode) == "bulk_points" and
      Map.get(context, :request_item_count, 0) > 1
  end

  defp group_summary?(context) when is_map(context) do
    present_text?(Map.get(context, :request_group_id)) and
      present_text?(Map.get(context, :request_group_progress))
  end

  defp stage_actions(context) do
    HistoricalWorkflowActionPolicy.stage_actions(context, stage_action_definitions())
  end

  defp group_stage_actions(context) do
    HistoricalWorkflowActionPolicy.group_stage_actions(context, stage_action_definitions())
  end

  defp stage_action_definitions do
    [
      %{stage: "requested", label: "Request", icon: "hero-document-plus", class: "btn-outline"},
      %{
        stage: "approved",
        label: "Approve",
        icon: "hero-check",
        class: "btn-success btn-outline"
      },
      %{stage: "rejected", label: "Reject", icon: "hero-x-mark", class: "btn-error btn-outline"},
      %{stage: "started", label: "Start", icon: "hero-play", class: "btn-info btn-outline"},
      %{
        stage: "completed",
        label: "Complete",
        icon: "hero-check-circle",
        class: "btn-success btn-outline"
      },
      %{
        stage: "failed",
        label: "Fail",
        icon: "hero-exclamation-triangle",
        class: "btn-warning btn-outline"
      }
    ]
  end

  defp job_status?(context) when is_map(context) do
    present_text?(Map.get(context, :job_id)) and present_text?(Map.get(context, :job_status))
  end

  defp corrected_run_id(context) do
    case Map.get(context, :run_id) do
      run_id when is_binary(run_id) and run_id != "" -> "#{run_id}-corrected"
      _run_id -> ""
    end
  end

  defp job_status_class("completed"), do: "border-success/40 bg-success/10 text-success-content"
  defp job_status_class("failed"), do: "border-error/40 bg-error/10 text-error-content"
  defp job_status_class("running"), do: "border-info/40 bg-info/10 text-info-content"
  defp job_status_class(_status), do: "border-base-300/70 bg-base-100/60 text-base-content"

  defp action_outcome_class("ok"), do: "border-success/40 bg-success/10 text-base-content"
  defp action_outcome_class("error"), do: "border-error/40 bg-error/10 text-base-content"
  defp action_outcome_class("degraded"), do: "border-warning/40 bg-warning/10 text-base-content"
  defp action_outcome_class("blocked"), do: "border-warning/40 bg-warning/10 text-base-content"
  defp action_outcome_class("no_op"), do: "border-info/40 bg-info/10 text-base-content"
  defp action_outcome_class(_status), do: "border-base-300/70 bg-base-100/60 text-base-content"

  defp action_outcome_badge_class("ok"), do: "badge-success"
  defp action_outcome_badge_class("error"), do: "badge-error"
  defp action_outcome_badge_class("degraded"), do: "badge-warning"
  defp action_outcome_badge_class("blocked"), do: "badge-warning"
  defp action_outcome_badge_class("no_op"), do: "badge-info"
  defp action_outcome_badge_class(_status), do: "badge-ghost"

  defp status_label("ok"), do: "Recorded"
  defp status_label("error"), do: "Failed"
  defp status_label("degraded"), do: "Degraded"
  defp status_label("blocked"), do: "Blocked"
  defp status_label("no_op"), do: "No-op"
  defp status_label(status) when is_binary(status), do: String.replace(status, "_", " ")

  defp action_label(action) when is_binary(action) do
    action
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp context_value(context, keys) when is_map(context) and is_list(keys) do
    Enum.find_value(keys, "", fn key ->
      value = Map.get(context, key)
      if present_text?(value), do: value
    end)
  end

  defp request_item_index(context) when is_map(context) do
    context
    |> Map.get(:request_item)
    |> split_request_item()
    |> elem(0)
  end

  defp request_item_count(context) when is_map(context) do
    context
    |> Map.get(:request_item)
    |> split_request_item()
    |> elem(1)
  end

  defp split_request_item(value) when is_binary(value) do
    case String.split(value, "/", parts: 2) do
      [index, count] -> {text_value(index) || "", text_value(count) || ""}
      _parts -> {"", ""}
    end
  end

  defp split_request_item(_value), do: {"", ""}

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""
end
