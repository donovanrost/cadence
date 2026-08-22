defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryPresentation do
  @moduledoc false

  @type audit_entry :: %{
          key: binary(),
          label: binary(),
          count: binary(),
          detail: binary() | nil
        }

  @type t :: %__MODULE__{
          visible: boolean(),
          unresolved: binary(),
          correction_task_count: binary(),
          handoff_summary: binary(),
          job_items: [binary()],
          retried_items: [binary()],
          corrected_items: [binary()],
          correction_task_items: [binary()],
          execution_audit_entries: [audit_entry()],
          execution_audit_summary: binary() | nil
        }

  defstruct visible: false,
            unresolved: "0",
            correction_task_count: "0",
            handoff_summary: "group unknown",
            job_items: [],
            retried_items: [],
            corrected_items: [],
            correction_task_items: [],
            execution_audit_entries: [],
            execution_audit_summary: nil

  @spec build(map() | nil) :: t()
  def build(workflow_context) when is_map(workflow_context) do
    correction_task_items = items(Map.get(workflow_context, :request_group_correction_tasks))
    execution_audit_entries = execution_audit_entries(workflow_context, correction_task_items)

    %__MODULE__{
      visible: visible?(workflow_context),
      unresolved: unresolved(workflow_context),
      correction_task_count: Integer.to_string(length(correction_task_items)),
      handoff_summary: handoff_summary(workflow_context),
      job_items: items(Map.get(workflow_context, :request_group_job_items)),
      retried_items: items(Map.get(workflow_context, :request_group_retried_items)),
      corrected_items: items(Map.get(workflow_context, :request_group_corrected_items)),
      correction_task_items: correction_task_items,
      execution_audit_entries: execution_audit_entries,
      execution_audit_summary: execution_audit_summary(execution_audit_entries)
    }
  end

  def build(_workflow_context), do: %__MODULE__{}

  defp visible?(workflow_context) do
    present_text?(Map.get(workflow_context, :request_group_failed_items)) or
      positive_text?(Map.get(workflow_context, :request_group_failed)) or
      positive_text?(Map.get(workflow_context, :request_group_resolved_failed)) or
      positive_text?(Map.get(workflow_context, :request_group_retry_resolved)) or
      positive_text?(Map.get(workflow_context, :request_group_correction_requested)) or
      present_text?(Map.get(workflow_context, :request_group_retried_items)) or
      present_text?(Map.get(workflow_context, :request_group_corrected_items)) or
      present_text?(Map.get(workflow_context, :request_group_correction_tasks))
  end

  defp unresolved(workflow_context) do
    failed = integer_value(Map.get(workflow_context, :request_group_failed))
    resolved = integer_value(Map.get(workflow_context, :request_group_resolved_failed))

    failed
    |> Kernel.-(resolved)
    |> max(0)
    |> Integer.to_string()
  end

  defp handoff_summary(workflow_context) do
    [
      "group #{Map.get(workflow_context, :request_group_id) || "unknown"}",
      Map.get(workflow_context, :request_group_state),
      summary_part("progress", Map.get(workflow_context, :request_group_progress)),
      summary_part("jobs", Map.get(workflow_context, :request_group_job_progress)),
      summary_part("failed", Map.get(workflow_context, :request_group_failed)),
      summary_part("retryable", Map.get(workflow_context, :request_group_retryable_failed)),
      summary_part("correction", Map.get(workflow_context, :request_group_nonretryable_failed)),
      summary_part("resolved", Map.get(workflow_context, :request_group_resolved_failed)),
      summary_part("failed items", Map.get(workflow_context, :request_group_failed_items))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  defp summary_part(_label, nil), do: nil
  defp summary_part(_label, ""), do: nil
  defp summary_part(label, value), do: "#{label} #{value}"

  defp execution_audit_entries(workflow_context, correction_task_items) do
    [
      audit_entry("requested", "Requested", Map.get(workflow_context, :request_group_requested)),
      audit_entry("approved", "Approved", Map.get(workflow_context, :request_group_approved)),
      audit_entry("started", "Started", Map.get(workflow_context, :request_group_started)),
      audit_entry(
        "job_progress",
        "Job progress",
        Map.get(workflow_context, :request_group_job_progress),
        Map.get(workflow_context, :request_group_job_items)
      ),
      audit_entry("completed", "Completed", Map.get(workflow_context, :request_group_completed)),
      audit_entry(
        "failed",
        "Failed",
        Map.get(workflow_context, :request_group_failed),
        Map.get(workflow_context, :request_group_failed_items)
      ),
      audit_entry(
        "retried",
        "Retried",
        Map.get(workflow_context, :request_group_retry_resolved),
        Map.get(workflow_context, :request_group_retried_items)
      ),
      audit_entry(
        "corrected",
        "Corrected",
        Map.get(workflow_context, :request_group_correction_requested),
        Map.get(workflow_context, :request_group_corrected_items)
      ),
      audit_entry(
        "correction_started",
        "Correction started",
        Map.get(workflow_context, :request_group_correction_started)
      ),
      audit_entry(
        "correction_completed",
        "Correction completed",
        Map.get(workflow_context, :request_group_correction_completed)
      ),
      audit_entry(
        "correction_superseded",
        "Correction superseded",
        Map.get(workflow_context, :request_group_correction_superseded)
      ),
      audit_entry(
        "recovered",
        "Recovered failures",
        Map.get(workflow_context, :request_group_resolved_failed)
      ),
      audit_entry(
        "recovery_tasks",
        "Recovery tasks",
        Integer.to_string(length(correction_task_items)),
        Map.get(workflow_context, :request_group_correction_tasks)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp audit_entry(key, label, count, detail \\ nil) do
    count = audit_count(count)
    detail = audit_detail(detail)

    if positive_text?(count) or present_text?(detail) do
      %{key: key, label: label, count: count, detail: detail}
    end
  end

  defp audit_count(value) when is_integer(value), do: Integer.to_string(value)

  defp audit_count(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> "0"
      Regex.match?(~r/^\d+$/, value) -> value
      true -> value
    end
  end

  defp audit_count(_value), do: "0"

  defp audit_detail(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp audit_detail(_value), do: nil

  defp execution_audit_summary(entries) when entries == [], do: nil

  defp execution_audit_summary(entries) do
    Enum.map_join(entries, "; ", fn entry -> "#{entry.key} #{entry.count}" end)
  end

  defp items(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp items(_value), do: []

  defp positive_text?(value) when is_integer(value), do: value > 0

  defp positive_text?(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number > 0
      _other -> false
    end
  end

  defp positive_text?(_value), do: false

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> 0
    end
  end

  defp integer_value(_value), do: 0
end
