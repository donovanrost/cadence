defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]
  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome
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

  test "apply_bulk_revision_decision stores partial-failure action outcome and refreshes activity" do
    request_event =
      comparison_review_request_event(
        event_id: "review-request-1",
        payload: %{
          "schema" => "dashboard_comparison_review_request.v1",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => 2,
          "open_placement_ids" => ["placement-1", "placement-2"],
          "open_findings" => %{
            "schema" => "dashboard_comparison_open_findings.v1",
            "runtime_query" => %{
              "realm" => "telemetry",
              "data_source_id" => "source-1",
              "source_binding_id" => "binding-1"
            },
            "findings" => [
              %{
                "placement_id" => "placement-1",
                "title" => "Bus voltage",
                "decision_status" => "unhandled",
                "observation_identity_id" => "identity-1"
              },
              %{
                "placement_id" => "placement-2",
                "title" => "Current",
                "decision_status" => "unhandled",
                "observation_identity_id" => "identity-2"
              }
            ]
          }
        }
      )

    socket =
      socket()
      |> assign(:dashboard_lifecycle_events, [request_event])
      |> ComparisonReviewEvents.apply_bulk_revision_decision(
        %{
          "review" => %{
            "source_request_event_id" => "review-request-1",
            "decision" => "mark_conflict",
            "confirmed" => "confirmed",
            "decision_reason" => "dashboard_comparison_review_mark_conflict"
          }
        },
        apply_comparison_review_bulk_decision: fn items, decision, attrs, opts ->
          assert Enum.map(items, & &1.observation_identity_id) == ["identity-1", "identity-2"]

          assert Enum.map(items, & &1.evidence_ref["placement_id"]) == [
                   "placement-1",
                   "placement-2"
                 ]

          assert decision == "mark_conflict"
          assert opts == [dashboard_runtime_invalidation?: true]
          assert attrs.organization_id == "org-1"
          assert attrs.mission_id == "mission-1"
          assert attrs.realm == "telemetry"
          assert attrs.data_source_id == "source-1"
          assert attrs.binding_id == "binding-1"
          assert attrs.correction_workflow_id == "review-request-1"
          assert attrs.decision_reason == "dashboard_comparison_review_mark_conflict"

          {:ok,
           %{
             workflow_id: "review-request-1",
             applied: 1,
             failed: 1,
             result_event_ids: "decision-event-1"
           }}
        end,
        dashboard_runtime_invalidation?: true,
        list_dashboard_lifecycle_events: fn organization_id, mission_id, dashboard_id ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"
          assert dashboard_id == "dashboard-1"
          [request_event]
        end,
        dashboard_comparison_review_queue: fn _organization_id,
                                              _mission_id,
                                              _dashboard_id,
                                              lifecycle_events ->
          assert lifecycle_events == [request_event]
          %{count: 1, requests: [request_event], request_ids_attr: "review-request-1"}
        end,
        put_flash: fn socket, kind, message ->
          assign(socket, :flash_call, {kind, message})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert %ComparisonReviewActionOutcome{} =
             outcome =
             socket.assigns.dashboard_comparison_review_action_outcome

    assert outcome.status == :degraded
    assert outcome.kind == :warning
    assert outcome.reason == "comparison_review_bulk_decision_partially_applied"
    assert outcome.decision == "mark_conflict"
    assert outcome.decision_reason == "dashboard_comparison_review_mark_conflict"
    assert outcome.source_request_event_id == "review-request-1"
    assert outcome.workflow_id == "review-request-1"
    assert outcome.requested == 2
    assert outcome.applied == 1
    assert outcome.failed == 1
    assert outcome.result_event_ids == "decision-event-1"
    assert outcome.target_event_id == "review-request-1"

    assert socket.assigns.dashboard_activity_filter == :open_comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == "review-request-1"

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1",
             "selected_placement" => nil
           }

    assert socket.assigns.flash_call ==
             {:info, "Comparison review decisions applied to 1 findings; 1 failed."}
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
