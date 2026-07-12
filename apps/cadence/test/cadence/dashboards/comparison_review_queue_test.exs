defmodule Cadence.Dashboards.ComparisonReviewQueueTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias Cadence.Dashboards.LifecycleEvent

  test "open_summary keeps unresolved request ids and placement ids together" do
    events = [
      request_event("request-1",
        payload: %{
          "open_placement_ids" => ["placement-1", "placement-2"],
          "open_count" => 2,
          "open_findings" => %{
            "findings" => [
              %{
                "placement_id" => "placement-1",
                "scope_kind" => "transport",
                "scope_ids" => ["transport-alpha", "transport-beta"],
                "contact_ids" => ["contact-alpha", "contact-beta"],
                "resource_id" => "transport-alpha",
                "transport_id" => "transport-alpha",
                "source_endpoint_id" => "endpoint-alpha",
                "ground_station_id" => "dss-14",
                "scope_link_id" => "link-alpha"
              }
            ]
          }
        }
      ),
      request_event("request-2",
        payload: %{
          open_findings: %{
            findings: [
              %{placement_id: "placement-3", decision_status: "unhandled"}
            ]
          }
        }
      ),
      resolution_event("resolution-2", source_request_event_id: "request-2")
    ]

    assert ComparisonReviewQueue.open_summary(events) == %{
             count: 1,
             count_text: "1",
             requests: [Enum.at(events, 0)],
             request_ids: ["request-1"],
             request_ids_attr: "request-1",
             placement_ids: ["placement-1", "placement-2"],
             placements_attr: "placement-1,placement-2",
             scope_kind: "transport",
             scope_kinds: ["transport"],
             scope_kinds_attr: "transport",
             scope_ids: ["transport-alpha", "transport-beta"],
             scope_ids_attr: "transport-alpha,transport-beta",
             contact_ids: ["contact-alpha", "contact-beta"],
             contact_ids_attr: "contact-alpha,contact-beta",
             resource_ids: ["transport-alpha"],
             resource_ids_attr: "transport-alpha",
             transport_ids: ["transport-alpha"],
             transport_ids_attr: "transport-alpha",
             source_endpoint_ids: ["endpoint-alpha"],
             source_endpoint_ids_attr: "endpoint-alpha",
             ground_station_ids: ["dss-14"],
             ground_station_ids_attr: "dss-14",
             scope_link_ids: ["link-alpha"],
             scope_link_ids_attr: "link-alpha"
           }
  end

  test "request_summary normalizes request payload details" do
    event =
      request_event("request-1",
        payload: %{
          schema: "dashboard_comparison_review_request.v1",
          request_kind: "comparison_open_findings_review",
          open_count: "bad-count",
          open_findings: %{
            findings: [
              %{
                placement_id: "placement-1",
                title: "Voltage",
                decision_status: "unhandled",
                scope_kind: "transport",
                scope_ids: ["transport-alpha", "transport-beta"],
                contact_ids: ["contact-alpha", "contact-beta"],
                resource_id: "transport-alpha",
                transport_id: "transport-alpha",
                source_endpoint_id: "endpoint-alpha",
                ground_station_id: "dss-14",
                scope_link_id: "link-alpha"
              },
              %{
                "placement_id" => "placement-2",
                "state" => "missing",
                "scope_kind" => "transport",
                "scope_id" => "transport-gamma",
                "contact_id" => "contact-gamma"
              }
            ]
          }
        }
      )

    summary = ComparisonReviewQueue.request_summary(event, [])

    assert summary.event_id == "request-1"
    assert summary.schema == "dashboard_comparison_review_request.v1"
    assert summary.kind == "comparison_open_findings_review"
    assert summary.status == "open"
    assert summary.open_count == 2
    assert summary.open_count_text == "2"
    assert summary.placement_ids == ["placement-1", "placement-2"]
    assert summary.placements_attr == "placement-1,placement-2"
    assert summary.scope_kind == "transport"
    assert summary.scope_ids == ["transport-alpha", "transport-beta", "transport-gamma"]
    assert summary.scope_ids_attr == "transport-alpha,transport-beta,transport-gamma"
    assert summary.contact_ids == ["contact-alpha", "contact-beta", "contact-gamma"]
    assert summary.contact_ids_attr == "contact-alpha,contact-beta,contact-gamma"
    assert summary.resource_ids == ["transport-alpha"]
    assert summary.transport_ids == ["transport-alpha"]
    assert summary.source_endpoint_ids == ["endpoint-alpha"]
    assert summary.ground_station_ids == ["dss-14"]
    assert summary.scope_link_ids == ["link-alpha"]
    assert summary.operational_context.scope_ids == summary.scope_ids

    assert Enum.map(summary.findings, &ComparisonReviewQueue.finding_summary/1) == [
             %{
               placement_id: "placement-1",
               title: "Voltage",
               state: "",
               decision_status: "unhandled"
             },
             %{
               placement_id: "placement-2",
               title: "placement-2",
               state: "missing",
               decision_status: ""
             }
           ]
  end

  test "request_summary links a request to its resolution" do
    request = request_event("request-1")
    resolution = resolution_event("resolution-1", source_request_event_id: "request-1")

    summary = ComparisonReviewQueue.request_summary(request, [request, resolution])

    assert summary.status == "resolved"
    assert summary.resolved? == true
    assert summary.resolution_event_id == "resolution-1"
  end

  test "resolution_summary normalizes placement context" do
    event =
      resolution_event("resolution-1",
        source_request_event_id: "request-1",
        payload: %{
          "disposition" => "review_completed",
          "resolution_reason" => "Reviewed by ops",
          "selected_placement_id" => "placement-1",
          "affected_placement_ids" => ["placement-1", nil, ""],
          "workflow_intent" => %{
            "kind" => "bulk_correction_authority_review",
            "action" => "request_comparison_review",
            "selection_count" => 2
          },
          "source_open_count" => 2,
          "source_open_placement_ids" => ["placement-1", "placement-2"],
          "source_scope_kind" => "transport",
          "source_scope_ids" => ["transport-alpha", "transport-beta"],
          "source_contact_ids" => ["contact-alpha", "contact-beta"],
          "source_resource_ids" => ["transport-alpha"],
          "source_transport_ids" => ["transport-alpha"],
          "source_endpoint_ids" => ["endpoint-alpha"],
          "source_ground_station_ids" => ["dss-14"],
          "source_scope_link_ids" => ["link-alpha"],
          "source_bulk_decision_actionable_count" => 1,
          "source_bulk_decision_actionable_placement_ids" => ["placement-1"],
          "source_bulk_decision_skipped_count" => 1,
          "source_bulk_decision_skipped_placement_ids" => ["placement-2"],
          "source_bulk_decision_skipped_reasons" => ["missing_observation_identity"]
        }
      )

    assert ComparisonReviewQueue.resolution_summary(event) == %{
             source_request_event_id: "request-1",
             disposition: "review_completed",
             resolution_reason: "Reviewed by ops",
             selected_placement_id: "placement-1",
             affected_placement_ids: ["placement-1"],
             affected_placements_attr: "placement-1",
             affected_placements_text: "placement-1",
             workflow_intent_kind: "bulk_correction_authority_review",
             workflow_intent_action: "request_comparison_review",
             workflow_selection_count_text: "2",
             source_open_count_text: "2",
             source_open_placement_ids: ["placement-1", "placement-2"],
             source_open_placements_attr: "placement-1,placement-2",
             source_scope_kind: "transport",
             source_scope_ids: ["transport-alpha", "transport-beta"],
             source_scope_ids_attr: "transport-alpha,transport-beta",
             source_contact_ids: ["contact-alpha", "contact-beta"],
             source_contact_ids_attr: "contact-alpha,contact-beta",
             source_resource_ids: ["transport-alpha"],
             source_resource_ids_attr: "transport-alpha",
             source_transport_ids: ["transport-alpha"],
             source_transport_ids_attr: "transport-alpha",
             source_endpoint_ids: ["endpoint-alpha"],
             source_endpoint_ids_attr: "endpoint-alpha",
             source_ground_station_ids: ["dss-14"],
             source_ground_station_ids_attr: "dss-14",
             source_scope_link_ids: ["link-alpha"],
             source_scope_link_ids_attr: "link-alpha",
             source_bulk_decision_actionable_count_text: "1",
             source_bulk_decision_actionable_placement_ids: ["placement-1"],
             source_bulk_decision_actionable_placements_attr: "placement-1",
             source_bulk_decision_skipped_count_text: "1",
             source_bulk_decision_skipped_placement_ids: ["placement-2"],
             source_bulk_decision_skipped_placements_attr: "placement-2",
             source_bulk_decision_skipped_reasons: ["missing_observation_identity"],
             source_bulk_decision_skipped_reasons_attr: "missing_observation_identity"
           }
  end

  defp request_event(event_id, opts \\ []) do
    lifecycle_event(event_id, :comparison_review_requested,
      payload:
        Keyword.get(opts, :payload, %{
          "schema" => "dashboard_comparison_review_request.v1",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => 1,
          "open_placement_ids" => ["placement-1"],
          "open_findings" => %{
            "schema" => "dashboard_comparison_open_findings.v1",
            "findings" => [%{"placement_id" => "placement-1"}]
          }
        })
    )
  end

  defp resolution_event(event_id, opts) do
    source_request_event_id = Keyword.fetch!(opts, :source_request_event_id)

    payload =
      %{
        "schema" => "dashboard_comparison_review_resolution.v1",
        "source_request_event_id" => source_request_event_id,
        "disposition" => "review_completed",
        "affected_placement_ids" => ["placement-1"]
      }
      |> Map.merge(Keyword.get(opts, :payload, %{}))
      |> Map.put_new("source_request_event_id", source_request_event_id)

    lifecycle_event(event_id, :comparison_review_resolved, payload: payload)
  end

  defp lifecycle_event(event_id, event_type, opts) do
    LifecycleEvent.new(%{
      dashboard_lifecycle_event_id: event_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      event_type: event_type,
      dashboard_version: 1,
      previous_lifecycle_state: "active",
      current_lifecycle_state: "active",
      occurred_at: ~U[2026-06-24 12:00:00Z],
      payload: Keyword.get(opts, :payload, %{})
    })
  end
end
