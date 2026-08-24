defmodule CadenceWeb.OpsDashboardShowLive.WidgetSourceHealthStatusComponentsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponents

  test "source-status presentation preserves degraded health as actionable warning" do
    presentation =
      source_badge_presentation(%{
        state: :degraded,
        severity: :warning,
        data_state: :ready,
        logical_sources: [:telemetry],
        data_source_ids: ["questdb-flight"],
        source_binding_ids: ["binding-flight"],
        source_health_states: [:degraded],
        source_health_reasons: [:source_schema_probe_failed],
        source_health_event_ids: ["source-health-event-1"]
      })

    attrs = presentation["badge"]["attrs"]

    assert presentation["badge"]["class"] ==
             "badge badge-xs gap-1 cursor-pointer join-item badge-warning"

    assert attrs["phx-click"] == "open_evidence"
    assert attrs["data-widget-source-badge-label"] == "Source degraded"
    assert attrs["data-widget-source-badge-severity"] == "warning"
    assert attrs["data-widget-source-badge-health-state"] == "degraded"
    assert attrs["data-widget-source-badge-health-reason"] == "source_schema_probe_failed"
    assert attrs["data-widget-source-badge-health-event-id"] == "source-health-event-1"
    assert attrs["phx-value-source-health-event-id"] == "source-health-event-1"
  end

  test "source-status presentation opens evidence with only health event context" do
    presentation =
      source_badge_presentation(%{
        state: :degraded,
        severity: :warning,
        data_state: :ready,
        source_health_states: [:degraded],
        source_health_reasons: [:source_schema_probe_failed],
        source_health_event_ids: ["source-health-event-1"]
      })

    attrs = presentation["badge"]["attrs"]
    assert attrs["phx-click"] == "open_evidence"
    assert attrs["phx-value-source-health-event-id"] == "source-health-event-1"
  end

  defp source_badge_presentation(source_status) do
    source_status
    |> WidgetSourceStatusComponents.source_status_badge_presentation("mission-1")
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
