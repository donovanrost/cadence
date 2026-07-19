defmodule Cadence.Telemetry.DataManagement.WorkflowPolicy do
  @moduledoc false

  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup

  def action_policy(context) when is_map(context) do
    %{
      retry_job: retry_job_action_policy(context),
      retry_group_failed_jobs: retry_group_action_policy(context),
      correction_request: correction_request_action_policy(context)
    }
  end

  def action_policy(_context), do: action_policy(%{})

  def stage_action_policy(context, stage)
      when is_map(context) and (is_atom(stage) or is_binary(stage)) do
    stage = text(stage)
    current_stage = text(get_attr(context, :stage))
    eligible? = stage_transition_eligible?(context, stage, current_stage)

    %{
      id: "stage_#{stage}",
      kind: :stage,
      eligible?: eligible?,
      disabled?: not eligible?,
      reason: stage_action_reason(context, stage, current_stage, eligible?)
    }
  end

  def stage_action_policy(_context, stage), do: stage_action_policy(%{}, stage)

  def group_stage_action_policy(context, stage)
      when is_map(context) and (is_atom(stage) or is_binary(stage)) do
    stage = text(stage)
    eligible_count = group_stage_eligible_count(context, stage)
    eligible? = eligible_count > 0

    %{
      id: "group_stage_#{stage}",
      kind: :group_stage,
      eligible?: eligible?,
      disabled?: not eligible?,
      eligible_count: eligible_count,
      reason: group_stage_action_reason(context, eligible_count, eligible?)
    }
  end

  def group_stage_action_policy(_context, stage), do: group_stage_action_policy(%{}, stage)

  def explanation_summary(context) when is_map(context) do
    [
      &late_data_explanation/1,
      &dispatch_failure_explanation/1,
      &failure_explanation/1,
      &relationship_explanation/1,
      &completion_explanation/1
    ]
    |> Enum.find_value(& &1.(context))
    |> Kernel.||(default_explanation(context))
  end

  def explanation_summary(_context), do: explanation_summary(%{})

  @doc false
  @spec retry_job_action_policy(map()) :: map()
  def retry_job_action_policy(context) do
    eligible? =
      job_status?(context) and get_attr(context, :job_status) == "failed" and
        present_text?(get_attr(context, :event_id)) and
        get_attr(context, :retryable) != "false" and
        get_attr(context, :recovery_action) != "correct_workflow_request"

    %{
      id: "retry_job",
      kind: :retry_job,
      eligible?: eligible?,
      disabled?: not eligible?,
      reason: retry_job_action_reason(context, eligible?)
    }
  end

  @doc false
  @spec retry_group_action_policy(map()) :: map()
  def retry_group_action_policy(context) do
    retryable_count = integer(get_attr(context, :request_group_retryable_failed))
    eligible? = retryable_count > 0 and present_text?(get_attr(context, :request_group_id))

    %{
      id: "retry_group_failed_jobs",
      kind: :retry_group_failed_jobs,
      eligible?: eligible?,
      disabled?: not eligible?,
      eligible_count: retryable_count,
      reason: retry_group_action_reason(context, retryable_count, eligible?)
    }
  end

  @doc false
  @spec correction_request_action_policy(map()) :: map()
  def correction_request_action_policy(context) do
    eligible? =
      job_status?(context) and get_attr(context, :job_status) == "failed" and
        get_attr(context, :recovery_action) == "correct_workflow_request" and
        present_text?(get_attr(context, :event_id))

    %{
      id: "correction_request",
      kind: :correction_request,
      eligible?: eligible?,
      disabled?: not eligible?,
      reason: correction_request_action_reason(context, eligible?)
    }
  end

  defp stage_transition_eligible?(context, stage, current_stage) do
    BackfillLifecycleGroup.stage_eligible?(stage, current_stage) and
      not (stage == "started" and job_status?(context))
  end

  defp stage_action_reason(_context, _stage, _current_stage, true),
    do: "stage_transition_available"

  defp stage_action_reason(context, stage, current_stage, false) do
    cond do
      stage == current_stage ->
        "already_in_stage"

      stage == "started" and job_status?(context) ->
        "job_already_exists"

      not BackfillLifecycleGroup.stage_eligible?(stage, current_stage) ->
        "stage_transition_out_of_order"

      true ->
        "stage_transition_ineligible"
    end
  end

  defp group_stage_action_reason(_context, _eligible_count, true),
    do: "eligible_group_items"

  defp group_stage_action_reason(context, eligible_count, false) do
    cond do
      not present_text?(get_attr(context, :request_group_id)) ->
        "request_group_missing"

      eligible_count <= 0 ->
        "no_eligible_group_items"

      true ->
        "group_stage_ineligible"
    end
  end

  defp retry_job_action_reason(_context, true), do: "failed_job_retryable"

  defp retry_job_action_reason(context, false) do
    cond do
      not job_status?(context) ->
        "job_status_missing"

      get_attr(context, :job_status) != "failed" ->
        "job_not_failed"

      not present_text?(get_attr(context, :event_id)) ->
        "source_event_missing"

      get_attr(context, :recovery_action) == "correct_workflow_request" ->
        "correction_required"

      get_attr(context, :retryable) == "false" ->
        "retry_blocked"

      true ->
        "retry_ineligible"
    end
  end

  defp retry_group_action_reason(_context, _retryable_count, true),
    do: "retryable_group_failures"

  defp retry_group_action_reason(context, retryable_count, false) do
    cond do
      not present_text?(get_attr(context, :request_group_id)) ->
        "request_group_missing"

      retryable_count <= 0 ->
        "no_retryable_group_failures"

      true ->
        "group_retry_ineligible"
    end
  end

  defp correction_request_action_reason(_context, true),
    do: "correction_request_required"

  defp correction_request_action_reason(context, false) do
    cond do
      not job_status?(context) ->
        "job_status_missing"

      get_attr(context, :job_status) != "failed" ->
        "job_not_failed"

      get_attr(context, :recovery_action) != "correct_workflow_request" ->
        "correction_not_required"

      not present_text?(get_attr(context, :event_id)) ->
        "source_event_missing"

      true ->
        "correction_ineligible"
    end
  end

  defp group_stage_eligible_count(context, stage) do
    context
    |> get_attr(group_stage_eligible_key(stage))
    |> integer()
  end

  defp group_stage_eligible_key("requested"), do: :request_group_request_eligible
  defp group_stage_eligible_key("approved"), do: :request_group_approve_eligible
  defp group_stage_eligible_key("rejected"), do: :request_group_reject_eligible
  defp group_stage_eligible_key("started"), do: :request_group_start_eligible
  defp group_stage_eligible_key("completed"), do: :request_group_complete_eligible
  defp group_stage_eligible_key("failed"), do: :request_group_fail_eligible
  defp group_stage_eligible_key(_stage), do: :request_group_request_eligible

  defp job_status?(context) when is_map(context) do
    present_text?(get_attr(context, :job_id)) and
      present_text?(get_attr(context, :job_status))
  end

  defp job_status?(_context), do: false

  defp text(value) when value in [nil, ""], do: nil
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> 0
    end
  end

  defp integer(_value), do: 0

  defp present_text?(value), do: is_binary(value) and value != ""

  defp late_data_explanation(context) do
    case text(get_attr(context, :event_type)) do
      "late_data_accepted" ->
        %{
          severity: :success,
          state: "late_data_accepted",
          badge: "accepted",
          reason: "late_data_accepted"
        }

      "late_data_rejected" ->
        %{
          severity: :warning,
          state: "late_data_rejected",
          badge: "rejected",
          reason: "late_data_rejected"
        }

      _event_type ->
        nil
    end
  end

  defp failure_explanation(context) do
    case text(get_attr(context, :stage)) do
      "failed" ->
        if get_attr(context, :retryable) in [false, "false", "0", 0] do
          %{
            severity: :error,
            state: "failed_correction_required",
            badge: "correction",
            reason: "failed_correction_required"
          }
        else
          %{
            severity: :error,
            state: "failed_retryable",
            badge: "failed",
            reason: "failed_retryable"
          }
        end

      _stage ->
        nil
    end
  end

  defp dispatch_failure_explanation(context) do
    case {text(get_attr(context, :stage)), text(get_attr(context, :job_status))} do
      {"started", "failed"} ->
        %{
          severity: :warning,
          state: "dispatch_failed",
          badge: "degraded",
          reason: "workflow_dispatch_failed"
        }

      _other ->
        nil
    end
  end

  defp relationship_explanation(context) do
    cond do
      present_text?(get_attr(context, :correction_source_event_id)) ->
        %{
          severity: :warning,
          state: "correction",
          badge: "correction",
          reason: "correction_replacement_event"
        }

      present_text?(get_attr(context, :retry_source_event_id)) ->
        %{
          severity: :info,
          state: "retry",
          badge: "retry",
          reason: "retry_replacement_event"
        }

      true ->
        nil
    end
  end

  defp completion_explanation(context) do
    case text(get_attr(context, :stage)) do
      "completed" ->
        %{
          severity: :success,
          state: "completed",
          badge: "completed",
          reason: "workflow_completed"
        }

      _stage ->
        nil
    end
  end

  defp default_explanation(context) do
    stage = text(get_attr(context, :stage))
    event_type = text(get_attr(context, :event_type))

    %{
      severity: :info,
      state: stage || event_type || "recorded",
      badge: stage || "recorded",
      reason: "historical_data_workflow_recorded"
    }
  end

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
