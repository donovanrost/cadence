defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecycleEmptyRowsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.RenderWidget
  alias CadenceWeb.OpsDashboardShowLive.Components

  test "empty row widgets expose no-data lifecycle body notices" do
    for {type, notice} <- [
          {:status_matrix, "No current rows."},
          {:data_table, "No rows for this table."},
          {:state_timeline, "No state transitions in this time range."},
          {:event_timeline, "No events in this time range."}
        ] do
      html =
        render_component(&Components.widget/1,
          widget: row_widget(type),
          placement_id: "placement-1",
          data: empty_lifecycle_row_data(type),
          compare_data: nil,
          point: nil,
          spacecraft: [],
          backfill: nil,
          limit_markers: [],
          event_markers: [],
          selected_data_ref: nil,
          context_spacecraft_id: "spacecraft-1",
          chart_epoch: 1,
          edit_mode?: false,
          warnings: []
        )

      document = LazyHTML.from_fragment(html)

      assert ["no_data"] =
               document
               |> LazyHTML.query("[data-widget-body-notice]")
               |> LazyHTML.attribute("data-widget-body-notice")

      assert html =~ notice
    end
  end

  defp data_table do
    %RenderWidget{
      widget_id: "widget-1",
      type: :data_table,
      title: "Telemetry Rows",
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.voltage"
      },
      options: %{precision: 2}
    }
  end

  defp event_timeline do
    %RenderWidget{
      widget_id: "widget-1",
      type: :event_timeline,
      title: "Events",
      binding: %{mode: :context, source: :events, point_id: "events"},
      options: %{}
    }
  end

  defp row_widget(:event_timeline), do: event_timeline()

  defp row_widget(type) when type in [:status_matrix, :data_table, :state_timeline] do
    %{data_table() | type: type}
  end

  defp empty_lifecycle_row_data(:event_timeline) do
    %{event_timeline_data() | rows: [], lifecycle_state: :no_data}
  end

  defp empty_lifecycle_row_data(type)
       when type in [:status_matrix, :data_table, :state_timeline] do
    %{
      lifecycle_table_data(:no_data)
      | kind: type,
        rows: []
    }
  end

  defp event_timeline_data do
    %{
      kind: :event_timeline,
      rows: [],
      links: [],
      data_management: nil,
      stale?: false,
      unresolved?: false,
      engine_backed?: true,
      lifecycle_state: :ready
    }
  end

  defp lifecycle_table_data(state) do
    %{
      kind: :data_table,
      rows: [
        %{
          observable_id: "tlm.hk.battery_voltage",
          label: "Battery voltage",
          source: :telemetry,
          value: 12.25,
          unit: "V",
          quality_state: :good,
          normalized_state: :green,
          limit_state: :green,
          receipt_time: ~U[2026-06-17 12:00:00Z],
          links: []
        }
      ],
      links: [],
      data_management: nil,
      stale?: state == :stale,
      unresolved?: false,
      engine_backed?: true,
      lifecycle_state: state,
      lifecycle: %{
        state: state,
        severity: lifecycle_severity(state),
        reason_codes: lifecycle_reasons(state),
        warning_codes: []
      }
    }
  end

  defp lifecycle_severity(:no_data), do: :info
  defp lifecycle_severity(:stale), do: :warning
  defp lifecycle_severity(:partial), do: :warning
  defp lifecycle_severity(:retention_gap), do: :error
  defp lifecycle_severity(:error), do: :error
  defp lifecycle_severity(:unsupported), do: :error

  defp lifecycle_reasons(state), do: [state]
end
