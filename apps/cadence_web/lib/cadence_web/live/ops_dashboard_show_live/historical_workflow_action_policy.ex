defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionPolicy do
  @moduledoc false

  alias Cadence.Reads.TelemetryDataManagement, as: DataManagement

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionPolicyAction,
    as: Action

  @type action :: Action.t()

  def build(context) when is_map(context) do
    context
    |> DataManagement.historical_data_workflow_action_policy()
    |> Map.merge(%{
      retry_job: retry_job_action(context),
      retry_group_failed_jobs: retry_group_failed_jobs_action(context),
      correction_request: correction_request_action(context)
    })
  end

  def build(_context), do: build(%{})

  def stage_actions(context, action_definitions)
      when is_map(context) and is_list(action_definitions) do
    Enum.map(action_definitions, &stage_action(context, &1))
  end

  def stage_actions(_context, action_definitions) when is_list(action_definitions) do
    stage_actions(%{}, action_definitions)
  end

  def group_stage_actions(context, action_definitions)
      when is_map(context) and is_list(action_definitions) do
    Enum.map(action_definitions, &group_stage_action(context, &1))
  end

  def group_stage_actions(_context, action_definitions) when is_list(action_definitions) do
    group_stage_actions(%{}, action_definitions)
  end

  def stage_action(context, action_definition) when is_map(action_definition) do
    stage = Map.get(action_definition, :stage)

    decision =
      DataManagement.historical_data_workflow_stage_action_policy(
        context,
        stage
      )

    action_definition
    |> Map.merge(decision)
    |> Map.merge(%{
      preview: individual_stage_preview(context, action_definition, decision.eligible?),
      explanation: individual_stage_explanation(context, action_definition, decision.reason),
      state_summary: individual_stage_state_summary(context, decision.reason),
      available_when: individual_stage_available_when(decision.reason)
    })
    |> Action.normalize()
  end

  def group_stage_action(context, action_definition) when is_map(action_definition) do
    stage = Map.get(action_definition, :stage)

    decision =
      DataManagement.historical_data_workflow_group_stage_action_policy(
        context,
        stage
      )

    action_definition
    |> Map.merge(decision)
    |> Map.merge(%{
      preview:
        group_stage_preview(
          context,
          action_definition,
          decision.eligible_count,
          decision.eligible?
        ),
      explanation: group_stage_explanation(context, action_definition, decision.reason),
      state_summary:
        group_stage_state_summary(
          context,
          action_definition,
          decision.eligible_count,
          decision.reason
        ),
      correction_tasks: group_stage_correction_tasks(context, action_definition),
      available_when: group_stage_available_when(decision.reason, action_definition)
    })
    |> Action.normalize()
  end

  def retry_job_action(context) when is_map(context) do
    decision =
      DataManagement.historical_data_workflow_action_policy(context).retry_job

    Map.merge(decision, %{
      label: "Retry job",
      preview: retry_job_preview(context, decision.eligible?),
      explanation: retry_job_explanation(decision.reason),
      state_summary: job_state_summary(context, decision.reason),
      available_when: retry_job_available_when(decision.reason)
    })
    |> Action.normalize()
  end

  def retry_job_action(_context), do: retry_job_action(%{})

  def retry_group_failed_jobs_action(context) when is_map(context) do
    decision =
      DataManagement.historical_data_workflow_action_policy(context).retry_group_failed_jobs

    Map.merge(decision, %{
      label: "Retry failed items",
      preview: retry_group_preview(context, decision.eligible_count, decision.eligible?),
      explanation: retry_group_explanation(decision.reason),
      state_summary: retry_group_state_summary(context, decision.reason),
      available_when: retry_group_available_when(decision.reason)
    })
    |> Action.normalize()
  end

  def retry_group_failed_jobs_action(_context), do: retry_group_failed_jobs_action(%{})

  def correction_request_action(context) when is_map(context) do
    decision =
      DataManagement.historical_data_workflow_action_policy(context).correction_request

    Map.merge(decision, %{
      label: "Create corrected request",
      preview: correction_preview(context, decision.eligible?),
      explanation: correction_explanation(decision.reason),
      state_summary: job_state_summary(context, decision.reason),
      available_when: correction_available_when(decision.reason)
    })
    |> Action.normalize()
  end

  def correction_request_action(_context), do: correction_request_action(%{})

  defp individual_stage_preview(context, action_definition, true) do
    "Record #{action_label(action_definition)} transition for run #{Map.get(context, :run_id)}"
  end

  defp individual_stage_preview(_context, action_definition, false) do
    "#{action_label(action_definition)} transition is not currently eligible"
  end

  defp individual_stage_explanation(_context, _action_definition, "stage_transition_available"),
    do: "This workflow transition can be recorded now."

  defp individual_stage_explanation(_context, action_definition, "already_in_stage") do
    "#{String.capitalize(action_label(action_definition))} is already the current workflow stage."
  end

  defp individual_stage_explanation(_context, _action_definition, "job_already_exists"),
    do: "A workflow job is already recorded for this run."

  defp individual_stage_explanation(_context, action_definition, "stage_transition_out_of_order") do
    "#{String.capitalize(action_label(action_definition))} does not follow the current workflow stage."
  end

  defp individual_stage_explanation(_context, action_definition, _reason) do
    "#{String.capitalize(action_label(action_definition))} is not eligible for the current lifecycle state."
  end

  defp individual_stage_available_when("stage_transition_available"), do: nil

  defp individual_stage_available_when("already_in_stage"),
    do: "Choose a transition that advances or changes the current stage."

  defp individual_stage_available_when("job_already_exists"),
    do: "Resolve or inspect the existing workflow job before starting another one."

  defp individual_stage_available_when("stage_transition_out_of_order"),
    do: "Record the prerequisite workflow stage before this transition."

  defp individual_stage_available_when(_reason),
    do: "Refresh the lifecycle event after the workflow reaches an eligible state."

  defp individual_stage_state_summary(context, "stage_transition_available"),
    do: compact_summary(["current stage #{text_or_unknown(Map.get(context, :stage))}"])

  defp individual_stage_state_summary(context, "already_in_stage"),
    do: compact_summary(["current stage #{text_or_unknown(Map.get(context, :stage))}"])

  defp individual_stage_state_summary(context, "job_already_exists") do
    compact_summary([
      "job #{text_or_unknown(Map.get(context, :job_id))}",
      "status #{text_or_unknown(Map.get(context, :job_status))}"
    ])
  end

  defp individual_stage_state_summary(context, "stage_transition_out_of_order"),
    do: compact_summary(["current stage #{text_or_unknown(Map.get(context, :stage))}"])

  defp individual_stage_state_summary(context, _reason),
    do: compact_summary(["current stage #{text_or_unknown(Map.get(context, :stage))}"])

  defp group_stage_preview(context, action_definition, eligible_count, true) do
    "Record #{action_label(action_definition)} transition for #{eligible_count} eligible items in request group #{Map.get(context, :request_group_id)}"
  end

  defp group_stage_preview(_context, action_definition, _eligible_count, false) do
    "No request-group items are eligible for #{action_label(action_definition)}"
  end

  defp group_stage_explanation(_context, action_definition, "eligible_group_items") do
    "#{String.capitalize(action_label(action_definition))} can be recorded for eligible request-group items."
  end

  defp group_stage_explanation(_context, _action_definition, "request_group_missing"),
    do: "No request group is attached to this workflow event."

  defp group_stage_explanation(_context, action_definition, "no_eligible_group_items") do
    "No request-group items are eligible for #{action_label(action_definition)}."
  end

  defp group_stage_explanation(_context, action_definition, _reason) do
    "#{String.capitalize(action_label(action_definition))} is not eligible for this request group."
  end

  defp group_stage_available_when("eligible_group_items", _action_definition), do: nil

  defp group_stage_available_when("request_group_missing", _action_definition),
    do: "Open a bulk workflow event with a request group."

  defp group_stage_available_when("no_eligible_group_items", action_definition) do
    "At least one item must become eligible for #{action_label(action_definition)}."
  end

  defp group_stage_available_when(_reason, _action_definition),
    do: "Refresh the request group after item eligibility changes."

  defp group_stage_state_summary(context, action_definition, eligible_count, _reason) do
    stage = Map.get(action_definition, :stage)
    correction_tasks = group_stage_correction_tasks(context, action_definition)

    compact_summary([
      "group #{text_or_unknown(Map.get(context, :request_group_id))}",
      "progress #{text_or_unknown(Map.get(context, :request_group_progress))}",
      "eligible #{text_value(eligible_count)} for #{stage || "stage"}",
      correction_task_summary(correction_tasks)
    ])
  end

  defp correction_task_summary(nil), do: nil
  defp correction_task_summary(""), do: nil

  defp correction_task_summary(tasks) do
    label =
      tasks
      |> split_task_rows()
      |> case do
        [_task] -> "correction task"
        _tasks -> "correction tasks"
      end

    "#{label} #{tasks}"
  end

  defp group_stage_correction_tasks(context, action_definition) do
    action = action_label(action_definition)

    context
    |> Map.get(:request_group_correction_tasks)
    |> split_task_rows()
    |> Enum.filter(&String.contains?(&1, " next #{action}"))
    |> case do
      [] -> nil
      tasks -> Enum.join(tasks, "; ")
    end
  end

  defp split_task_rows(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_task_rows(_value), do: []

  defp retry_job_preview(context, true) do
    "Retry failed job #{Map.get(context, :job_id)} from event #{Map.get(context, :event_id)}"
  end

  defp retry_job_preview(_context, false), do: "Retry is not currently eligible"

  defp retry_job_explanation("failed_job_retryable"),
    do: "This failed workflow job can be retried."

  defp retry_job_explanation("job_status_missing"), do: "No workflow job status is available."
  defp retry_job_explanation("job_not_failed"), do: "The workflow job is not failed."
  defp retry_job_explanation("source_event_missing"), do: "The source lifecycle event is missing."

  defp retry_job_explanation("correction_required"),
    do: "This failure requires a corrected workflow request."

  defp retry_job_explanation("retry_blocked"), do: "The workflow failure is marked non-retryable."
  defp retry_job_explanation(_reason), do: "Retry is not eligible for this workflow job."

  defp retry_job_available_when("failed_job_retryable"), do: nil

  defp retry_job_available_when("job_status_missing"),
    do: "Select a lifecycle event with a recorded workflow job."

  defp retry_job_available_when("job_not_failed"),
    do: "Retry becomes available after a job fails."

  defp retry_job_available_when("source_event_missing"),
    do: "Open the persisted lifecycle event that recorded the failed job."

  defp retry_job_available_when("correction_required"),
    do: "Create a corrected workflow request instead of retrying this job."

  defp retry_job_available_when("retry_blocked"),
    do: "Use a correction request or resolve the failure outside retry."

  defp retry_job_available_when(_reason),
    do: "Refresh the workflow job after its retry state changes."

  defp job_state_summary(context, _reason) do
    compact_summary([
      "job #{text_or_unknown(Map.get(context, :job_id))}",
      "status #{text_or_unknown(Map.get(context, :job_status))}",
      "retryable #{text_or_unknown(Map.get(context, :retryable))}",
      "recovery #{text_or_unknown(Map.get(context, :recovery_action))}"
    ])
  end

  defp retry_group_preview(context, retryable_count, true) do
    "Retry #{retryable_count} failed jobs in request group #{Map.get(context, :request_group_id)}"
  end

  defp retry_group_preview(_context, _retryable_count, false) do
    "No retryable group failures are currently eligible"
  end

  defp retry_group_explanation("retryable_group_failures"),
    do: "This request group has retryable failed workflow jobs."

  defp retry_group_explanation("request_group_missing"),
    do: "No request group is attached to this workflow event."

  defp retry_group_explanation("no_retryable_group_failures"),
    do: "This request group has no retryable failed workflow jobs."

  defp retry_group_explanation(_reason), do: "Group retry is not eligible for this workflow."

  defp retry_group_available_when("retryable_group_failures"), do: nil

  defp retry_group_available_when("request_group_missing"),
    do: "Open a bulk workflow event with a request group."

  defp retry_group_available_when("no_retryable_group_failures"),
    do: "At least one failed item must become retryable."

  defp retry_group_available_when(_reason),
    do: "Refresh the request group after failed-item retryability changes."

  defp retry_group_state_summary(context, _reason) do
    compact_summary([
      "group #{text_or_unknown(Map.get(context, :request_group_id))}",
      "progress #{text_or_unknown(Map.get(context, :request_group_progress))}",
      "retryable failed #{text_or_unknown(Map.get(context, :request_group_retryable_failed))}",
      "nonretryable failed #{text_or_unknown(Map.get(context, :request_group_nonretryable_failed))}"
    ])
  end

  defp correction_preview(context, true) do
    "Create a corrected request for failed event #{Map.get(context, :event_id)}"
  end

  defp correction_preview(_context, false), do: "Correction request is not currently eligible"

  defp correction_explanation("correction_request_required"),
    do: "This failure requires a corrected workflow request."

  defp correction_explanation("job_status_missing"), do: "No workflow job status is available."
  defp correction_explanation("job_not_failed"), do: "The workflow job is not failed."

  defp correction_explanation("correction_not_required"),
    do: "This failure does not require a corrected workflow request."

  defp correction_explanation("source_event_missing"),
    do: "The source lifecycle event is missing."

  defp correction_explanation(_reason),
    do: "A corrected workflow request is not eligible for this failure."

  defp correction_available_when("correction_request_required"), do: nil

  defp correction_available_when("job_status_missing"),
    do: "Select a lifecycle event with a recorded workflow job."

  defp correction_available_when("job_not_failed"),
    do: "Correction becomes available after a job fails with a correction recovery action."

  defp correction_available_when("correction_not_required"),
    do:
      "Correction becomes available when the failure recovery action requires a corrected request."

  defp correction_available_when("source_event_missing"),
    do: "Open the persisted lifecycle event that recorded the failed job."

  defp correction_available_when(_reason),
    do: "Refresh the workflow job after its recovery action changes."

  defp action_label(action_definition) do
    action_definition
    |> Map.get(:label, "workflow")
    |> String.downcase()
  end

  defp compact_summary(parts) do
    parts
    |> Enum.reject(&blank?/1)
    |> Enum.join("; ")
  end

  defp text_or_unknown(nil), do: "unknown"
  defp text_or_unknown(""), do: "unknown"
  defp text_or_unknown(value), do: text_value(value) || "unknown"

  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
