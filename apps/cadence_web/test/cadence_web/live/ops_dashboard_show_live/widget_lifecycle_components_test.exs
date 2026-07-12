defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecycleComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.RenderWidget
  alias CadenceWeb.OpsDashboardShowLive.Components

  test "widget header exposes stable lifecycle attributes and badges" do
    for {state, severity, label} <- [
          {:no_data, :info, "No Data"},
          {:stale, :warning, "Stale"},
          {:partial, :warning, "Partial"},
          {:retention_gap, :error, "Retention Gap"},
          {:error, :error, "Source Error"},
          {:unsupported, :error, "Unsupported"}
        ] do
      html =
        render_component(&Components.widget/1,
          widget: value_tile(),
          placement_id: "placement-1",
          data: lifecycle_point_data(state),
          compare_data: nil,
          point: %{unit: "V"},
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
      selector = ~s([data-widget-lifecycle-state="#{state}"])
      expected_severity = Atom.to_string(severity)
      expected_state = Atom.to_string(state)

      assert [^expected_severity] =
               document
               |> LazyHTML.query(selector)
               |> LazyHTML.attribute("data-widget-lifecycle-severity")

      assert [^expected_state] =
               document
               |> LazyHTML.query(selector)
               |> LazyHTML.attribute("data-widget-lifecycle-reasons")

      assert html =~ label
    end
  end

  test "widget unsupported notice explains selected context mismatch" do
    data =
      :unsupported
      |> lifecycle_point_data()
      |> put_in([:lifecycle, :warning_codes], [:unsupported_observable_scope])

    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: data,
        compare_data: nil,
        point: %{unit: "V"},
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

    assert html =~ "This widget does not support the selected context."

    document = LazyHTML.from_fragment(html)

    assert ["unsupported"] =
             document
             |> LazyHTML.query("[data-widget-body-notice]")
             |> LazyHTML.attribute("data-widget-body-notice")
  end

  test "time series source failure renders a body notice instead of an empty chart" do
    html =
      render_component(&Components.widget/1,
        widget: time_series(),
        placement_id: "placement-1",
        data: lifecycle_point_data(:error),
        compare_data: nil,
        point: %{unit: "V"},
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

    assert ["error"] =
             document
             |> LazyHTML.query("[data-widget-body-notice]")
             |> LazyHTML.attribute("data-widget-body-notice")

    assert [] =
             document
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"]))
             |> LazyHTML.attribute("phx-hook")

    assert html =~ "This widget cannot load because its source failed."
  end

  test "partial data table keeps rows visible and explains degraded coverage" do
    html =
      render_component(&Components.widget/1,
        widget: data_table(),
        placement_id: "placement-1",
        data: lifecycle_table_data(:partial),
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

    assert ["partial"] =
             document
             |> LazyHTML.query("[data-widget-body-notice]")
             |> LazyHTML.attribute("data-widget-body-notice")

    assert ["tlm.hk.battery_voltage"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-row")

    assert html =~ "This widget is showing partial data"
  end

  defp value_tile do
    %RenderWidget{
      widget_id: "widget-1",
      type: :value_tile,
      title: "Voltage",
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.voltage"
      },
      options: %{precision: 2}
    }
  end

  defp time_series do
    %RenderWidget{
      widget_id: "widget-1",
      type: :time_series,
      title: "Voltage",
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.voltage"
      },
      options: %{precision: 2, window_seconds: 300}
    }
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

  defp point_data(value) do
    %{
      kind: :point,
      sample: %{
        raw_value: value,
        engineering_value: value,
        receipt_time: ~U[2026-06-17 12:00:00Z],
        generation_time: ~U[2026-06-17 12:00:00Z],
        quality_state: :good
      },
      limit_event: nil,
      links: [],
      data_management: nil,
      stale?: false,
      unresolved?: false,
      engine_backed?: true,
      lifecycle: %{state: :ready},
      lifecycle_state: :ready
    }
  end

  defp lifecycle_point_data(state) do
    sample =
      if state in [:no_data, :retention_gap, :error, :unsupported] do
        nil
      else
        point_data(42).sample
      end

    %{
      point_data(42)
      | sample: sample,
        stale?: state == :stale,
        lifecycle_state: state,
        lifecycle: %{
          state: state,
          severity: lifecycle_severity(state),
          reason_codes: lifecycle_reasons(state),
          warning_codes: []
        }
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
