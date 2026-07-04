defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyContext do
  @moduledoc false

  def build(inspector) when is_map(inspector) do
    rows = Map.get(inspector, :rows, [])
    context_rows = Map.get(inspector, :context_rows, [])

    %{
      source_event_id: row_value(rows, "Backfill lifecycle event"),
      source_event_type: row_value(rows, "Event type"),
      run_id: row_value(rows, "Backfill run"),
      dashboard_time_mode:
        row_value(rows, "Dashboard context time mode") || row_value(context_rows, "Time mode"),
      dashboard_replay_run_id:
        row_value(rows, "Dashboard context replay run") || row_value(context_rows, "Replay run"),
      dashboard_limit_mode:
        row_value(rows, "Dashboard context limit mode") || row_value(context_rows, "Limit mode"),
      realm: row_value(rows, "Realm"),
      data_source_id: row_value(rows, "Data source"),
      source_binding_id: row_value(rows, "Source binding"),
      observable_id: row_value(rows, "Observable"),
      point_id: row_value(rows, "Point"),
      source_from: row_value(rows, "Source from"),
      source_to: row_value(rows, "Source to"),
      receipt_from: row_value(rows, "Receipt from"),
      receipt_to: row_value(rows, "Receipt to"),
      sample_count: row_value(rows, "Sample count"),
      authority: row_value(rows, "Authority"),
      reason: row_value(rows, "Reason")
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

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
