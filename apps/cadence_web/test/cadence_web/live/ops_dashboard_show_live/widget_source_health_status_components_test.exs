defmodule CadenceWeb.OpsDashboardShowLive.WidgetSourceHealthStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponents

  test "source_status_badge renders degraded source health as actionable warning" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: %{
          state: :degraded,
          severity: :warning,
          data_state: :ready,
          logical_sources: [:telemetry],
          data_source_ids: ["questdb-flight"],
          source_binding_ids: ["binding-flight"],
          source_health_states: [:degraded],
          source_health_reasons: [:source_schema_probe_failed],
          source_health_event_ids: ["source-health-event-1"]
        },
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("phx-click")

    assert ["Source degraded"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-label")

    assert ["warning"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-severity")

    assert ["degraded"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-health-state")

    assert ["source_schema_probe_failed"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-health-reason")

    assert ["source-health-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-health-event-id")

    assert ["source-health-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("phx-value-source-health-event-id")
  end

  test "source_status_badge opens evidence when only source health event context is present" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: %{
          state: :degraded,
          severity: :warning,
          data_state: :ready,
          source_health_states: [:degraded],
          source_health_reasons: [:source_schema_probe_failed],
          source_health_event_ids: ["source-health-event-1"]
        },
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("phx-click")

    assert ["source-health-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("phx-value-source-health-event-id")
  end
end
