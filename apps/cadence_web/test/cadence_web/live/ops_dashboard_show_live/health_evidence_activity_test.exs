defmodule CadenceWeb.OpsDashboardShowLive.HealthEvidenceActivityTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.HealthEvidenceActivity

  test "build links dashboard health evidence to a matching captured health activity event" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "snapshot_id" => "health-snapshot-1",
          "snapshot_schema" => "dashboard_health_snapshot.v1"
        }
      )

    inspector = %{
      kind: :dashboard_health,
      subject_rows: [
        %{label: "Health snapshot schema", value: "dashboard_health_snapshot.v1"},
        %{label: "Health snapshot", value: "health-snapshot-1"}
      ]
    }

    assert HealthEvidenceActivity.build(inspector, [event]) == %{
             render?: true,
             event: event,
             event_id: "dashboard-lifecycle-event-health",
             snapshot_id: "health-snapshot-1"
           }
  end

  test "build accepts direct snapshot ids on the inspector" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "snapshot" => %{
            "schema" => "dashboard_health_snapshot.v1",
            "snapshot_id" => "health-snapshot-direct"
          }
        }
      )

    inspector = %{kind: :dashboard_health, snapshot_id: "health-snapshot-direct"}

    assert %{
             render?: true,
             event_id: "dashboard-lifecycle-event-health",
             snapshot_id: "health-snapshot-direct"
           } = HealthEvidenceActivity.build(inspector, [event])
  end

  test "build does not link without a matching snapshot id" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{"snapshot_id" => "health-snapshot-1"}
      )

    inspector = %{
      kind: :dashboard_health,
      subject_rows: [%{label: "Health snapshot", value: "health-snapshot-missing"}]
    }

    assert HealthEvidenceActivity.build(inspector, [event]) == %{
             render?: false,
             event: nil,
             event_id: nil,
             snapshot_id: "health-snapshot-missing"
           }
  end

  test "build ignores non-dashboard-health evidence" do
    event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    assert HealthEvidenceActivity.build(%{kind: :widget}, [event]) == %{
             render?: false,
             event: nil,
             event_id: nil,
             snapshot_id: nil
           }
  end

  test "snapshot_id returns nil for blank health snapshot evidence rows" do
    inspector = %{
      kind: :dashboard_health,
      subject_rows: [%{label: "Health snapshot", value: ""}]
    }

    assert HealthEvidenceActivity.snapshot_id(inspector) == nil
  end
end
