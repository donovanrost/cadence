defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponents

  test "event_details renders captured health snapshot metadata" do
    snapshot = %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => "health-snapshot-1",
      "state" => "attention",
      "severity" => "warning",
      "counts" => %{
        "widgets" => 6,
        "ready" => 2,
        "affected" => 4,
        "blocked" => 1,
        "stale" => 2,
        "degraded" => 1
      },
      "placement_ids" => %{
        "affected" => ["placement-1", "placement-2"],
        "blocked" => ["placement-3"],
        "stale" => ["placement-4"],
        "degraded" => ["placement-5"]
      }
    }

    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "source" => "operator",
          "snapshot_id" => "health-snapshot-1",
          "snapshot_schema" => "dashboard_health_snapshot.v1",
          "health_state" => "attention",
          "health_severity" => "warning",
          "captured_reason" => "pre-pass review",
          "snapshot" => snapshot
        }
      )

    html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)
    document = LazyHTML.from_fragment(html)

    assert ["health-snapshot-1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert ["dashboard_health_snapshot.v1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-schema")

    assert ["attention"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-state")

    assert ["widgets", "ready", "affected", "blocked", "stale", "degraded"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-count]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-count")

    assert ["6", "2", "4", "1", "2", "1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-count]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-count-value")

    assert ["affected", "blocked", "stale", "degraded"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-placements]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-placements")

    copy =
      LiveVue.Test.get_vue(html,
        id: "dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health-component"
      )

    assert copy.component == "ClipboardButton"

    assert copy.props["button_id"] ==
             "dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health"

    assert copy.props["button_class"] == "btn btn-ghost btn-xs shrink-0"
    assert copy.props["icon"] == "hero-clipboard-document"
    assert copy.props["icon_class"] == "h-3.5 w-3.5"
    assert copy.props["label"] == "Copy"

    assert copy.props["data_attrs"] == %{
             "data-dashboard-health-snapshot-event-copy" =>
               "dashboard-lifecycle-event-health",
             "data-dashboard-health-snapshot-id" => "health-snapshot-1",
             "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1"
           }

    snapshot_json = copy.props["clipboard_text"]

    assert Jason.decode!(snapshot_json) == snapshot
    assert copy.class == "contents"
    refute copy.ssr
  end

  test "event_details does not render non-health lifecycle events" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :published)

    html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)
    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")
  end
end
