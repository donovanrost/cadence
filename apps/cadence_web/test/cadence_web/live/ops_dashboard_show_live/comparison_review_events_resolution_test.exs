defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewEventsResolutionTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewEvents
  alias Phoenix.LiveView.Socket

  test "resolve_open_findings_review records a resolution event and refreshes activity" do
    request_event = comparison_review_request_event(actor_id: "user-1", dashboard_version: 1)

    resolution_event =
      comparison_review_resolution_event(actor_id: "user-1", dashboard_version: 1)

    socket =
      socket()
      |> ComparisonReviewEvents.resolve_open_findings_review(
        %{
          "review" => %{
            "source_request_event_id" => "dashboard-lifecycle-event-1",
            "disposition" => "review_completed",
            "resolution_reason" => "Reviewed",
            "selected_placement_id" => "placement-1",
            "affected_placement_ids" => "placement-1,placement-2"
          }
        },
        record_dashboard_comparison_review_resolution: fn organization_id,
                                                          mission_id,
                                                          dashboard_id,
                                                          payload,
                                                          opts ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          assert opts == [actor_id: "user-1"]
          assert payload["schema"] == "dashboard_comparison_review_resolution.v1"
          assert payload["source_request_event_id"] == "dashboard-lifecycle-event-1"
          assert payload["disposition"] == "review_completed"
          assert payload["resolution_reason"] == "Reviewed"
          assert payload["selected_placement_id"] == "placement-1"
          assert payload["affected_placement_ids"] == ["placement-1", "placement-2"]

          {:ok, resolution_event}
        end,
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          [request_event, resolution_event]
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [request_event, resolution_event]
    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :comparison_reviews

    assert socket.assigns.dashboard_activity_event_id ==
             resolution_event.dashboard_lifecycle_event_id

    assert socket.assigns.dashboard_review_placement_id == nil

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "comparison_reviews",
             "activity_event" => resolution_event.dashboard_lifecycle_event_id,
             "selected_placement" => nil
           }

    assert socket.assigns.flash_call == {:info, "Comparison review marked resolved."}
  end

  test "resolve_open_findings_review rejects missing request ids" do
    socket =
      socket()
      |> ComparisonReviewEvents.resolve_open_findings_review(
        %{"review" => %{"source_request_event_id" => ""}},
        record_dashboard_comparison_review_resolution: fn _organization_id,
                                                          _mission_id,
                                                          _dashboard_id,
                                                          _payload,
                                                          _opts ->
          flunk("should not record missing request ids")
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.flash_call ==
             {:error, "Comparison review request is no longer available."}
  end

  test "resolve_open_findings_review refreshes activity when already resolved" do
    request_event = comparison_review_request_event(actor_id: "user-1", dashboard_version: 1)

    resolution_event =
      comparison_review_resolution_event(actor_id: "user-1", dashboard_version: 1)

    socket =
      socket()
      |> ComparisonReviewEvents.resolve_open_findings_review(
        %{"review" => %{"source_request_event_id" => "dashboard-lifecycle-event-1"}},
        record_dashboard_comparison_review_resolution: fn _organization_id,
                                                          _mission_id,
                                                          _dashboard_id,
                                                          _payload,
                                                          _opts ->
          {:error, :comparison_review_already_resolved}
        end,
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          [request_event, resolution_event]
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [request_event, resolution_event]
    assert socket.assigns.flash_call == {:info, "Comparison review is already resolved."}
  end

  test "resolve_open_findings_review refreshes activity when placement context is stale" do
    request_event = comparison_review_request_event(actor_id: "user-1", dashboard_version: 1)

    socket =
      socket()
      |> ComparisonReviewEvents.resolve_open_findings_review(
        %{
          "review" => %{
            "source_request_event_id" => "dashboard-lifecycle-event-1",
            "selected_placement_id" => "placement-missing",
            "affected_placement_ids" => "placement-missing"
          }
        },
        record_dashboard_comparison_review_resolution: fn _organization_id,
                                                          _mission_id,
                                                          _dashboard_id,
                                                          _payload,
                                                          _opts ->
          {:error, :comparison_review_resolution_context_mismatch}
        end,
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          [request_event]
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [request_event]

    assert socket.assigns.flash_call ==
             {:error, "Comparison review context changed. Review the request and try again."}
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
end
