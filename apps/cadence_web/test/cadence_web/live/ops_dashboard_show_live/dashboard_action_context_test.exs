defmodule CadenceWeb.OpsDashboardShowLive.DashboardActionContextTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionContext
  alias Phoenix.LiveView.Socket

  test "scoped_ids and actor_opts derive command context from the socket" do
    socket = socket()

    assert DashboardActionContext.scoped_ids(socket) == {"org-1", "mission-1", "dashboard-1"}
    assert DashboardActionContext.actor_opts(socket) == [actor_id: "user-1"]

    anonymous_socket = put_in(socket.assigns.current_scope, %{organization_id: "org-1"})
    assert DashboardActionContext.actor_opts(anonymous_socket) == []
  end

  test "refresh_lifecycle_events assigns lifecycle events from scoped ids" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :health_snapshot_captured)

    socket =
      socket()
      |> DashboardActionContext.refresh_lifecycle_events(
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"

          [event]
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [event]
  end

  test "refresh_lifecycle_events_and_review_queue assigns lifecycle events and queue" do
    event = comparison_review_request_event()

    socket =
      socket()
      |> DashboardActionContext.refresh_lifecycle_events_and_review_queue(
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"

          [event]
        end,
        dashboard_comparison_review_queue: fn organization_id,
                                              mission_id,
                                              dashboard_id,
                                              lifecycle_events ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          assert lifecycle_events == [event]

          %{count: 1, requests: [event]}
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [event]
    assert socket.assigns.dashboard_comparison_review_queue == %{count: 1, requests: [event]}
  end

  test "target_activity focuses version activity and patches the route query" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :health_snapshot_captured)

    socket =
      socket()
      |> DashboardActionContext.target_activity(:health_snapshots, event,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

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
  end

  test "flash delegates to the configured flash function" do
    socket =
      socket()
      |> DashboardActionContext.flash(:info, "Saved.",
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.flash_call == {:info, "Saved."}
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
        dashboard_comparison_review_queue: %{count: 0, requests: []},
        panel: nil,
        dashboard_activity_filter: nil,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-1"
      }
    }
  end
end
