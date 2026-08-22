defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowExplanation do
  alias Cadence.Reads.TelemetryDataManagement, as: DataManagement

  @moduledoc false

  def build(context) when is_map(context) do
    summary =
      context
      |> DataManagement.historical_data_workflow_explanation_summary()
      |> decorate_summary()

    %{
      summary: summary,
      rows: rows(context),
      container_class: container_class(summary.severity),
      badge_class: badge_class(summary.severity)
    }
  end

  def build(_context), do: build(%{})

  defp decorate_summary(summary) when is_map(summary) do
    Map.put(summary, :summary, summary_text(Map.get(summary, :reason)))
  end

  defp summary_text("late_data_accepted"),
    do: "Late data was accepted for the inspected source window."

  defp summary_text("late_data_rejected"),
    do: "Late data was rejected for the inspected source window."

  defp summary_text("failed_correction_required"),
    do: "This workflow failed and needs a corrected request before it can continue."

  defp summary_text("failed_retryable"),
    do: "This workflow failed; retry eligibility and blockers are shown below."

  defp summary_text("workflow_dispatch_failed"),
    do: "This workflow was started, but the backing job failed before completion."

  defp summary_text("correction_replacement_event"),
    do: "This event records a corrected replacement for an earlier lifecycle event."

  defp summary_text("retry_replacement_event"),
    do: "This event records a retry of an earlier lifecycle event."

  defp summary_text("workflow_completed"),
    do: "This workflow completed for the inspected source window."

  defp summary_text(_reason),
    do: "This event records historical-data workflow state for the inspected source window."

  defp rows(context) when is_map(context) do
    [
      %{label: "Workflow", value: Map.get(context, :workflow) || "data_management"},
      %{label: "Run", value: Map.get(context, :run_id)},
      %{label: "Event", value: Map.get(context, :event_type)},
      %{label: "Stage", value: Map.get(context, :stage)},
      %{label: "Source", value: source(context)},
      %{label: "Window", value: window(context)},
      %{label: "Group", value: group(context)},
      %{label: "Progress", value: Map.get(context, :request_group_progress)},
      %{label: "Job", value: job(context)},
      %{label: "Failure", value: Map.get(context, :failure_code)},
      %{label: "Retryable", value: Map.get(context, :retryable)},
      %{label: "Recovery", value: Map.get(context, :recovery_action)},
      %{label: "Retry source", value: Map.get(context, :retry_source_event_id)},
      %{label: "Corrects", value: Map.get(context, :correction_source_event_id)},
      %{label: "Policy source", value: Map.get(context, :late_data_source_event_id)},
      %{label: "Policy", value: Map.get(context, :late_data_policy_decision)},
      %{label: "Selected samples", value: Map.get(context, :late_data_selected_samples)},
      %{label: "Projection", value: Map.get(context, :late_data_projection_effect)},
      %{label: "Write validity", value: Map.get(context, :late_data_write_validity)}
    ]
    |> Enum.filter(&present_text?(&1.value))
  end

  defp source(context) do
    [
      context_value(context, [:source_realm, :realm]),
      context_value(context, [:source_data_source_id, :data_source_id]),
      context_value(context, [:source_binding_id_override, :source_binding_id]),
      context_value(context, [:source_point_id, :point_id, :observable_id])
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
    |> empty_to_nil()
  end

  defp window(context) do
    from = context_value(context, [:source_from_override, :source_from])
    to = context_value(context, [:source_to_override, :source_to])

    if present_text?(from) or present_text?(to), do: "#{from || "?"} -> #{to || "?"}"
  end

  defp group(context) do
    request_group_id = Map.get(context, :request_group_id)

    if present_text?(request_group_id) do
      [request_group_id, Map.get(context, :request_group_state)]
      |> Enum.filter(&present_text?/1)
      |> Enum.join(" ")
    end
  end

  defp job(context) do
    job_id = Map.get(context, :job_id)
    job_status = Map.get(context, :job_status)

    cond do
      present_text?(job_id) and present_text?(job_status) -> "#{job_id} #{job_status}"
      present_text?(job_id) -> job_id
      true -> nil
    end
  end

  defp container_class(:success), do: "border-success/40 bg-success/10"
  defp container_class(:warning), do: "border-warning/40 bg-warning/10"
  defp container_class(:error), do: "border-error/40 bg-error/10"
  defp container_class(_severity), do: "border-info/40 bg-info/10"

  defp badge_class(:success), do: "badge-success"
  defp badge_class(:warning), do: "badge-warning"
  defp badge_class(:error), do: "badge-error"
  defp badge_class(_severity), do: "badge-info"

  defp context_value(context, keys) when is_map(context) and is_list(keys) do
    Enum.find_value(keys, "", fn key ->
      value = Map.get(context, key)
      if present_text?(value), do: value
    end)
  end

  defp present_text?(value), do: is_binary(value) and value != ""

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
