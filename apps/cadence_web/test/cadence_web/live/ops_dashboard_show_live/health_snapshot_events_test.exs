defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotEventsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotEvents
  alias Phoenix.LiveView.Socket

  test "capture_dashboard_health_snapshot records an auditable event and refreshes activity" do
    snapshot = health_snapshot()
    event = lifecycle_event("dashboard-lifecycle-event-1", :health_snapshot_captured)

    socket =
      socket()
      |> HealthSnapshotEvents.capture_dashboard_health_snapshot(
        %{"snapshot" => Jason.encode!(snapshot)},
        record_dashboard_health_snapshot: fn organization_id,
                                             mission_id,
                                             dashboard_id,
                                             payload,
                                             opts ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          assert payload == snapshot
          assert opts == [actor_id: "user-1"]

          {:ok, event}
        end,
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          [event]
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [event]
    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :health_snapshots
    assert socket.assigns.dashboard_activity_event_id == "dashboard-lifecycle-event-1"
    assert socket.assigns.dashboard_review_placement_id == nil

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => "dashboard-lifecycle-event-1",
             "selected_placement" => nil
           }

    assert socket.assigns.flash_call == {:info, "Dashboard health snapshot captured."}
  end

  test "capture_dashboard_health_snapshot rejects invalid snapshots" do
    socket =
      socket()
      |> HealthSnapshotEvents.capture_dashboard_health_snapshot(
        %{"snapshot" => Jason.encode!(%{"schema" => "dashboard_health_snapshot.v1"})},
        record_dashboard_health_snapshot: fn _organization_id,
                                             _mission_id,
                                             _dashboard_id,
                                             _payload,
                                             _opts ->
          flunk("should not record invalid health snapshots")
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.flash_call == {:error, "Dashboard health snapshot is invalid."}
  end

  test "capture_dashboard_health_snapshot handles archived dashboard errors" do
    socket =
      socket()
      |> HealthSnapshotEvents.capture_dashboard_health_snapshot(
        %{"snapshot" => Jason.encode!(health_snapshot())},
        record_dashboard_health_snapshot: fn _organization_id,
                                             _mission_id,
                                             _dashboard_id,
                                             _payload,
                                             _opts ->
          {:error, :dashboard_archived}
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.flash_call ==
             {:error, "Archived dashboards cannot capture health snapshots."}
  end

  defp socket do
    %Socket{
      assigns: %{
        __changed__: %{},
        current_scope: %{organization_id: "org-1", user: %{user_id: "user-1"}},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: %Document{
          organization_id: "org-1",
          mission_id: "mission-1",
          dashboard_id: "dashboard-1",
          name: "Ops"
        },
        dashboard_lifecycle_events: [],
        panel: nil,
        dashboard_activity_filter: nil,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: nil
      }
    }
  end

  defp health_snapshot do
    %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => "dashboard_health_snapshot_abc123",
      "dashboard_id" => "dashboard-1",
      "state" => "blocked"
    }
  end
end
