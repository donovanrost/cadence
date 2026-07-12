defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]
  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewEvents
  alias Phoenix.LiveView.Socket

  test "request_open_findings_review records an auditable request and refreshes activity" do
    open_findings =
      open_findings_payload(
        placement_ids: ["placement-1"],
        findings: [
          %{
            "placement_id" => "placement-1",
            "widget_id" => "widget-1",
            "decision_status" => "unhandled"
          }
        ]
      )

    event = comparison_review_request_event(actor_id: "user-1", dashboard_version: 1)

    socket =
      socket()
      |> ComparisonReviewEvents.request_open_findings_review(
        %{"review" => %{"open_findings" => Jason.encode!(open_findings)}},
        record_dashboard_comparison_review_request: fn organization_id,
                                                       mission_id,
                                                       dashboard_id,
                                                       payload,
                                                       opts ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          assert opts == [actor_id: "user-1"]
          assert payload["schema"] == "dashboard_comparison_review_request.v1"
          assert payload["request_kind"] == "comparison_open_findings_review"
          assert payload["open_count"] == 1
          assert payload["open_placement_ids"] == ["placement-1"]
          assert payload["open_findings"] == open_findings
          assert payload["workflow_intent"] == open_findings["workflow_intent"]

          {:ok, event}
        end,
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

          %{
            count: 1,
            count_text: "1",
            requests: [event],
            request_ids: [event.dashboard_lifecycle_event_id],
            request_ids_attr: event.dashboard_lifecycle_event_id,
            placement_ids: ["placement-1", "placement-2"],
            placements_attr: "placement-1,placement-2"
          }
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.dashboard_lifecycle_events == [event]
    assert socket.assigns.dashboard_comparison_review_queue.count == 1
    assert socket.assigns.dashboard_comparison_review_queue.requests == [event]
    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == event.dashboard_lifecycle_event_id
    assert socket.assigns.dashboard_review_placement_id == nil

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "comparison_reviews",
             "activity_event" => event.dashboard_lifecycle_event_id,
             "selected_placement" => nil
           }

    assert socket.assigns.flash_call == {:info, "Open comparison findings review requested."}
  end

  test "request_open_findings_review targets an existing open review request" do
    open_findings =
      open_findings_payload(
        placement_ids: ["placement-1"],
        findings: [
          %{
            "placement_id" => "placement-1",
            "widget_id" => "widget-1",
            "decision_status" => "unhandled"
          }
        ]
      )

    event = comparison_review_request_event(actor_id: "user-1", dashboard_version: 1)

    socket =
      socket()
      |> ComparisonReviewEvents.request_open_findings_review(
        %{"review" => %{"open_findings" => Jason.encode!(open_findings)}},
        record_dashboard_comparison_review_request: fn organization_id,
                                                       mission_id,
                                                       dashboard_id,
                                                       payload,
                                                       opts ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          assert opts == [actor_id: "user-1"]
          assert payload["open_placement_ids"] == ["placement-1"]

          {:error, {:comparison_review_already_requested, event}}
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
    assert socket.assigns.dashboard_activity_filter == :comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == event.dashboard_lifecycle_event_id
    assert socket.assigns.dashboard_review_placement_id == nil

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "comparison_reviews",
             "activity_event" => event.dashboard_lifecycle_event_id,
             "selected_placement" => nil
           }

    assert socket.assigns.flash_call == {:info, "Comparison review is already requested."}
  end

  test "request_open_findings_review rejects empty open finding payloads" do
    open_findings = %{
      "schema" => "dashboard_comparison_open_findings.v1",
      "findings" => []
    }

    socket =
      socket()
      |> ComparisonReviewEvents.request_open_findings_review(
        %{"review" => %{"open_findings" => Jason.encode!(open_findings)}},
        record_dashboard_comparison_review_request: fn _organization_id,
                                                       _mission_id,
                                                       _dashboard_id,
                                                       _payload,
                                                       _opts ->
          flunk("should not record empty review requests")
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end
      )

    assert socket.assigns.flash_call ==
             {:error, "No open comparison findings to request review for."}
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
