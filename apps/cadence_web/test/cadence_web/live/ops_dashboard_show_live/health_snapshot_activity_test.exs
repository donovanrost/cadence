defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivity

  test "build renders captured health snapshot details" do
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

    activity = HealthSnapshotActivity.build(event)

    assert %{
             present?: true,
             capture_schema: "dashboard_health_snapshot_capture.v1",
             snapshot_schema: "dashboard_health_snapshot.v1",
             snapshot_id: "health-snapshot-1",
             state: "attention",
             severity: "warning",
             source: "operator",
             captured_reason: "pre-pass review"
           } = activity

    assert [
             %{key: "widgets", label: "Widgets", value: "6"},
             %{key: "ready", label: "Ready", value: "2"},
             %{key: "affected", label: "Affected", value: "4"},
             %{key: "blocked", label: "Blocked", value: "1"},
             %{key: "stale", label: "Stale", value: "2"},
             %{key: "degraded", label: "Degraded", value: "1"}
           ] = activity.counts

    assert [
             %{key: "affected", label: "Affected", ids_attr: "placement-1,placement-2"},
             %{key: "blocked", label: "Blocked", ids_attr: "placement-3"},
             %{key: "stale", label: "Stale", ids_attr: "placement-4"},
             %{key: "degraded", label: "Degraded", ids_attr: "placement-5"}
           ] = Enum.map(activity.placements, &Map.take(&1, [:key, :label, :ids_attr]))

    assert Jason.decode!(activity.snapshot_json) == snapshot
    assert HealthSnapshotActivity.snapshot_id(event) == "health-snapshot-1"
  end

  test "build supports atom-key payloads and fallback count fields" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          schema: "dashboard_health_snapshot_capture.v1",
          snapshot: %{
            schema: "dashboard_health_snapshot.v1",
            snapshot_id: "health-snapshot-atom",
            state: :ready,
            severity: :nominal,
            widget_count: 3,
            placement_ids: %{
              affected: "placement-1,placement-2"
            }
          }
        }
      )

    activity = HealthSnapshotActivity.build(event)

    assert activity.present? == true
    assert activity.snapshot_schema == "dashboard_health_snapshot.v1"
    assert activity.snapshot_id == "health-snapshot-atom"
    assert activity.state == "ready"
    assert activity.severity == "nominal"
    assert HealthSnapshotActivity.snapshot_id(event) == "health-snapshot-atom"

    assert %{key: "widgets", value: "3"} = List.first(activity.counts)
    assert [%{key: "affected", ids: ["placement-1", "placement-2"]}] = activity.placements
  end

  test "build does not render non-health lifecycle events" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :published)

    assert HealthSnapshotActivity.build(event) == %{present?: false}
    assert HealthSnapshotActivity.snapshot_id(event) == nil
  end
end
