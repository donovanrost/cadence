defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewEventsBulkDecisionTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewEvents
  alias Phoenix.LiveView.Socket

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
                "observation_identity_id" => "identity-1",
                "scope_kind" => "transport",
                "scope_id" => "transport-alpha",
                "scope_ids" => ["transport-alpha", "transport-beta"],
                "resource_id" => "transport-alpha",
                "contact_id" => "contact-alpha",
                "contact_ids" => ["contact-alpha", "contact-beta"],
                "transport_id" => "transport-alpha",
                "source_endpoint_id" => "endpoint-alpha",
                "ground_station_id" => "dss-14",
                "scope_link_id" => "link-alpha"
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

          assert %{
                   "scope_kind" => "transport",
                   "scope_id" => "transport-alpha",
                   "scope_ids" => ["transport-alpha", "transport-beta"],
                   "resource_id" => "transport-alpha",
                   "contact_id" => "contact-alpha",
                   "contact_ids" => ["contact-alpha", "contact-beta"],
                   "transport_id" => "transport-alpha",
                   "source_endpoint_id" => "endpoint-alpha",
                   "ground_station_id" => "dss-14",
                   "scope_link_id" => "link-alpha"
                 } = List.first(items).evidence_ref["comparison_finding"]

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
    assert outcome.scope_kind == "transport"
    assert outcome.scope_ids == "transport-alpha,transport-beta"
    assert outcome.contact_ids == "contact-alpha,contact-beta"
    assert outcome.resource_ids == "transport-alpha"
    assert outcome.transport_ids == "transport-alpha"
    assert outcome.source_endpoint_ids == "endpoint-alpha"
    assert outcome.ground_station_ids == "dss-14"
    assert outcome.scope_link_ids == "link-alpha"

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
