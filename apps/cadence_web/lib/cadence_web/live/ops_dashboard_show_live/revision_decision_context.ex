defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionContext do
  @moduledoc false

  def build(inspector) when is_map(inspector) do
    rows = Map.get(inspector, :rows, [])
    context_rows = Map.get(inspector, :context_rows, [])

    %{
      source_decision_event_id: row_value(rows, "Revision decision event"),
      source_target: inspector |> Map.get(:target) |> text_value(),
      source_target_id: Map.get(inspector, :target_id),
      source_link_label: Map.get(inspector, :link_label),
      observation_identity_id: row_value(rows, "Observation identity"),
      source_decision: row_value(rows, "Decision"),
      dashboard_limit_mode:
        row_value(rows, "Dashboard context limit mode") || row_value(context_rows, "Limit mode"),
      realm: row_value(rows, "Realm"),
      data_source_id: row_value(rows, "Data source"),
      source_binding_id: row_value(rows, "Source binding"),
      canonical_observation_id:
        row_value(rows, "New canonical observation") ||
          row_value(rows, "Previous canonical observation"),
      canonical_sample_id:
        row_value(rows, "New canonical sample") || row_value(rows, "Previous canonical sample"),
      canonical_revision:
        row_value(rows, "New canonical revision") ||
          row_value(rows, "Previous canonical revision"),
      decision_reason: decision_reason(rows),
      correction_workflow_id: row_value(rows, "Correction workflow"),
      authority: row_value(rows, "Correction authority") || "dashboard_operator",
      comparison_state: row_value(rows, "State"),
      comparison_delta: row_value(rows, "Delta"),
      primary_sample_id: row_value(rows, "Primary sample"),
      compare_sample_id: row_value(rows, "Compare sample"),
      primary_data_view: row_value(rows, "Primary data view"),
      compare_data_view: row_value(rows, "Compare data view"),
      primary_count: row_value(rows, "Primary count"),
      compare_count: row_value(rows, "Compare count"),
      widget_id: row_value(rows, "Widget"),
      widget_title: row_value(rows, "Widget title")
    }
  end

  def build(_inspector), do: build(%{})

  defp row_value(rows, label) when is_list(rows) do
    rows
    |> Enum.find_value(fn
      %{label: ^label, value: value} -> empty_to_nil(value)
      %{"label" => ^label, "value" => value} -> empty_to_nil(value)
      _row -> nil
    end)
  end

  defp decision_reason(rows) do
    case row_value(rows, "Decision reason") do
      reason when is_binary(reason) and reason != "" -> reason
      _missing -> "dashboard_revision_decision"
    end
  end

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
