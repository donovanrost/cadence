defmodule Cadence.Dashboards.DocumentStoreLifecycleEventsTest do
  use Cadence.DataCase, async: false

  import Cadence.Dashboards.DocumentStoreFixtures

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{Document, LifecycleEvent, ValidationResult}

  test "records comparison review requests as dashboard lifecycle audit events" do
    persist_mission_scope("org-doc-comparison-review", "mission-doc-comparison-review")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-comparison-review",
        "mission-doc-comparison-review",
        "dashboard-doc-comparison-review"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-comparison-review", document)

    payload = %{
      "schema" => "dashboard_comparison_review_request.v1",
      "request_kind" => "comparison_open_findings_review",
      "open_count" => 1,
      "open_findings" => %{
        "schema" => "dashboard_comparison_open_findings.v1",
        "findings" => [%{"placement_id" => "placement-1"}]
      }
    }

    assert {:ok, %LifecycleEvent{} = event} =
             Dashboards.record_dashboard_comparison_review_request(
               "org-doc-comparison-review",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review",
               payload,
               actor_id: "user-reviewer",
               occurred_at: ~U[2026-06-24 12:00:00.000000Z]
             )

    assert event.event_type == :comparison_review_requested
    assert event.dashboard_version == Document.version(persisted)
    assert event.previous_lifecycle_state == "active"
    assert event.current_lifecycle_state == "active"
    assert event.actor_id == "user-reviewer"
    assert event.occurred_at == ~U[2026-06-24 12:00:00.000000Z]
    assert event.payload["schema"] == "dashboard_comparison_review_request.v1"
    assert event.payload["request_kind"] == "comparison_open_findings_review"
    assert event.payload["dashboard_name"] == persisted.name

    assert get_in(event.payload, ["open_findings", "findings"]) == [
             %{"placement_id" => "placement-1"}
           ]

    assert [%LifecycleEvent{event_type: :comparison_review_requested}] =
             Dashboards.list_lifecycle_events(
               "org-doc-comparison-review",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )
  end

  test "rejects duplicate open comparison review requests for overlapping placements" do
    persist_mission_scope("org-doc-comparison-review-duplicate", "mission-doc-comparison-review")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-comparison-review-duplicate",
        "mission-doc-comparison-review",
        "dashboard-doc-comparison-review"
      )

    assert {:ok, %Document{}} =
             Dashboards.persist_document("org-doc-comparison-review-duplicate", document)

    first_payload = %{
      "schema" => "dashboard_comparison_review_request.v1",
      "request_kind" => "comparison_open_findings_review",
      "open_count" => 2,
      "open_findings" => %{
        "schema" => "dashboard_comparison_open_findings.v1",
        "findings" => [
          %{"placement_id" => "placement-1"},
          %{"placement_id" => "placement-2"}
        ]
      }
    }

    second_payload = %{
      "schema" => "dashboard_comparison_review_request.v1",
      "request_kind" => "comparison_open_findings_review",
      "open_count" => 1,
      "open_placement_ids" => ["placement-2"],
      "open_findings" => %{
        "schema" => "dashboard_comparison_open_findings.v1",
        "findings" => [%{"placement_id" => "placement-2"}]
      }
    }

    assert {:ok, %LifecycleEvent{} = request_event} =
             Dashboards.record_dashboard_comparison_review_request(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review",
               first_payload,
               occurred_at: ~U[2026-06-24 12:00:00.000000Z]
             )

    assert {:error, {:comparison_review_already_requested, %LifecycleEvent{} = existing_event}} =
             Dashboards.record_dashboard_comparison_review_request(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review",
               second_payload,
               occurred_at: ~U[2026-06-24 12:05:00.000000Z]
             )

    assert existing_event.dashboard_lifecycle_event_id ==
             request_event.dashboard_lifecycle_event_id

    assert [
             %LifecycleEvent{event_type: :comparison_review_requested}
           ] =
             Dashboards.list_lifecycle_events(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )

    assert [^request_event] =
             Dashboards.list_open_comparison_review_requests(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )

    request_event_id = request_event.dashboard_lifecycle_event_id

    assert %{
             count: 1,
             request_ids: [^request_event_id],
             placement_ids: ["placement-1", "placement-2"]
           } =
             Dashboards.dashboard_comparison_review_queue(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )

    assert {:ok, %LifecycleEvent{event_type: :comparison_review_resolved}} =
             Dashboards.record_dashboard_comparison_review_resolution(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review",
               %{
                 "schema" => "dashboard_comparison_review_resolution.v1",
                 "source_request_event_id" => request_event.dashboard_lifecycle_event_id,
                 "affected_placement_ids" => ["placement-1", "placement-2"]
               },
               occurred_at: ~U[2026-06-24 12:10:00.000000Z]
             )

    assert {:ok, %LifecycleEvent{} = second_request_event} =
             Dashboards.record_dashboard_comparison_review_request(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review",
               second_payload,
               occurred_at: ~U[2026-06-24 12:15:00.000000Z]
             )

    assert second_request_event.event_type == :comparison_review_requested

    second_request_event_id = second_request_event.dashboard_lifecycle_event_id

    assert [^second_request_event] =
             Dashboards.list_open_comparison_review_requests(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )

    assert %{
             count: 1,
             request_ids: [^second_request_event_id],
             placement_ids: ["placement-2"]
           } =
             Dashboards.dashboard_comparison_review_queue(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )

    assert [
             %LifecycleEvent{event_type: :comparison_review_requested},
             %LifecycleEvent{event_type: :comparison_review_resolved},
             %LifecycleEvent{event_type: :comparison_review_requested}
           ] =
             Dashboards.list_lifecycle_events(
               "org-doc-comparison-review-duplicate",
               "mission-doc-comparison-review",
               "dashboard-doc-comparison-review"
             )
  end

  test "records dashboard health snapshots as lifecycle audit events" do
    persist_mission_scope("org-doc-health-snapshot", "mission-doc-health-snapshot")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-health-snapshot",
        "mission-doc-health-snapshot",
        "dashboard-doc-health-snapshot"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-health-snapshot", document)

    snapshot = health_snapshot()

    assert {:ok, %LifecycleEvent{} = event} =
             Dashboards.record_dashboard_health_snapshot(
               "org-doc-health-snapshot",
               "mission-doc-health-snapshot",
               "dashboard-doc-health-snapshot",
               snapshot,
               actor_id: "user-operator",
               captured_reason: "handover",
               occurred_at: ~U[2026-06-26 12:00:00.000000Z]
             )

    assert event.event_type == :health_snapshot_captured
    assert event.dashboard_version == Document.version(persisted)
    assert event.previous_lifecycle_state == "active"
    assert event.current_lifecycle_state == "active"
    assert event.actor_id == "user-operator"
    assert event.occurred_at == ~U[2026-06-26 12:00:00.000000Z]
    assert event.payload["schema"] == "dashboard_health_snapshot_capture.v1"
    assert event.payload["source"] == "dashboard_health_rollup"
    assert event.payload["dashboard_name"] == persisted.name
    assert event.payload["snapshot_id"] == snapshot["snapshot_id"]
    assert event.payload["snapshot_schema"] == "dashboard_health_snapshot.v1"
    assert event.payload["health_state"] == "blocked"
    assert event.payload["health_severity"] == "error"
    assert event.payload["captured_reason"] == "handover"
    assert event.payload["snapshot"] == snapshot

    assert [%LifecycleEvent{event_type: :health_snapshot_captured}] =
             Dashboards.list_lifecycle_events(
               "org-doc-health-snapshot",
               "mission-doc-health-snapshot",
               "dashboard-doc-health-snapshot"
             )
  end

  test "records dashboard publish readiness checks as lifecycle audit events" do
    persist_mission_scope("org-doc-readiness-check", "mission-doc-readiness-check")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-readiness-check",
        "mission-doc-readiness-check",
        "dashboard-doc-readiness-check"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-readiness-check", document)

    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :unsupported_source_capability,
            details: %{
              source_request_id: "request-telemetry-latest",
              logical_source: :telemetry,
              source_binding_id: "rehearsal-binding",
              data_source_id: "rehearsal-source",
              replay_run_id: "replay-run-7"
            }
          }
        }
      ]
    }

    assert {:ok, %LifecycleEvent{} = event} =
             Dashboards.record_dashboard_publish_readiness_check(
               "org-doc-readiness-check",
               "mission-doc-readiness-check",
               "dashboard-doc-readiness-check",
               persisted,
               validation,
               %{draft_version: 1, latest_version: 1, published_version: nil},
               actor_id: "user-operator",
               occurred_at: ~U[2026-06-27 12:00:00.000000Z]
             )

    assert event.event_type == :publish_readiness_checked
    assert event.dashboard_version == Document.version(persisted)
    assert event.previous_lifecycle_state == "active"
    assert event.current_lifecycle_state == "active"
    assert event.actor_id == "user-operator"
    assert event.payload["schema"] == "dashboard_publish_readiness_check.v1"
    assert event.payload["source"] == "dashboard_publish_readiness"
    assert event.payload["dashboard_name"] == persisted.name
    assert event.payload["result"] == "still_blocked"
    assert event.payload["issue_codes"] == ["unready_publish_source_request"]
    assert event.payload["source_warning_codes"] == ["unsupported_source_capability"]

    assert event.payload["source_evidence_contexts"] == [
             %{
               "warning_code" => "unsupported_source_capability",
               "source_request_id" => "request-telemetry-latest",
               "logical_source" => "telemetry",
               "source_binding_id" => "rehearsal-binding",
               "data_source_id" => "rehearsal-source",
               "replay_run_id" => "replay-run-7"
             }
           ]

    assert event.payload["freshness_state"] == "current"
    assert event.payload["freshness_reason"] == "draft_current"
    assert event.payload["freshness_reason_label"] == "draft current"

    assert event.payload["freshness_message"] ==
             "Publish readiness was evaluated against the current draft version."

    assert [%LifecycleEvent{event_type: :publish_readiness_checked}] =
             Dashboards.list_lifecycle_events(
               "org-doc-readiness-check",
               "mission-doc-readiness-check",
               "dashboard-doc-readiness-check"
             )
  end

  test "rejects publish readiness checks when the document belongs to another dashboard" do
    persist_mission_scope("org-doc-readiness-mismatch", "mission-doc-readiness-mismatch")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-readiness-mismatch",
        "mission-doc-readiness-mismatch",
        "dashboard-doc-readiness-mismatch"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-readiness-mismatch", document)

    assert {:error, :dashboard_document_mismatch} =
             Dashboards.record_dashboard_publish_readiness_check(
               "org-doc-readiness-mismatch",
               "mission-doc-readiness-mismatch",
               "different-dashboard-id",
               persisted,
               %ValidationResult{},
               nil,
               actor_id: "user-operator",
               occurred_at: ~U[2026-06-27 12:00:00.000000Z]
             )

    assert [] =
             Dashboards.list_lifecycle_events(
               "org-doc-readiness-mismatch",
               "mission-doc-readiness-mismatch",
               "dashboard-doc-readiness-mismatch"
             )
  end

  test "rejects invalid dashboard health snapshots" do
    persist_mission_scope(
      "org-doc-health-snapshot-invalid",
      "mission-doc-health-snapshot-invalid"
    )

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-health-snapshot-invalid",
        "mission-doc-health-snapshot-invalid",
        "dashboard-doc-health-snapshot-invalid"
      )

    assert {:ok, %Document{}} =
             Dashboards.persist_document("org-doc-health-snapshot-invalid", document)

    assert {:error, :invalid_health_snapshot} =
             Dashboards.record_dashboard_health_snapshot(
               "org-doc-health-snapshot-invalid",
               "mission-doc-health-snapshot-invalid",
               "dashboard-doc-health-snapshot-invalid",
               %{"schema" => "dashboard_health_snapshot.v1"}
             )
  end

  test "records comparison review resolutions against an existing request event" do
    persist_mission_scope(
      "org-doc-comparison-review-resolution",
      "mission-doc-comparison-review-resolution"
    )

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-comparison-review-resolution",
        "mission-doc-comparison-review-resolution",
        "dashboard-doc-comparison-review-resolution"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-comparison-review-resolution", document)

    assert {:ok, %LifecycleEvent{} = request_event} =
             Dashboards.record_dashboard_comparison_review_request(
               "org-doc-comparison-review-resolution",
               "mission-doc-comparison-review-resolution",
               "dashboard-doc-comparison-review-resolution",
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "open_count" => 2,
                 "open_placement_ids" => ["placement-1", "placement-2"],
                 "workflow_intent" => %{
                   "schema" => "dashboard_comparison_workflow_intent.v1",
                   "kind" => "bulk_correction_authority_review",
                   "source" => "dashboard_comparison_rollup",
                   "action" => "request_comparison_review",
                   "selection_kind" => "open_comparison_findings",
                   "selection_count" => 2,
                   "placement_ids" => ["placement-1", "placement-2"]
                 },
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "findings" => [
                     %{
                       "placement_id" => "placement-1",
                       "observation_identity_id" => "identity-1",
                       "decision_status" => "unhandled",
                       "scope_kind" => "transport",
                       "scope_ids" => ["transport-alpha", "transport-beta"],
                       "resource_id" => "transport-alpha",
                       "contact_ids" => ["contact-alpha", "contact-beta"],
                       "transport_id" => "transport-alpha",
                       "source_endpoint_id" => "endpoint-alpha",
                       "ground_station_id" => "dss-14",
                       "scope_link_id" => "link-alpha"
                     },
                     %{
                       "placement_id" => "placement-2",
                       "decision_status" => "unhandled"
                     }
                   ]
                 }
               },
               actor_id: "user-requester",
               occurred_at: ~U[2026-06-24 12:00:00.000000Z]
             )

    assert {:error, :comparison_review_resolution_context_mismatch} =
             Dashboards.record_dashboard_comparison_review_resolution(
               "org-doc-comparison-review-resolution",
               "mission-doc-comparison-review-resolution",
               "dashboard-doc-comparison-review-resolution",
               %{
                 "source_request_event_id" => request_event.dashboard_lifecycle_event_id,
                 "selected_placement_id" => "placement-missing",
                 "affected_placement_ids" => ["placement-1", "placement-missing"]
               }
             )

    assert {:ok, %LifecycleEvent{} = resolution_event} =
             Dashboards.record_dashboard_comparison_review_resolution(
               "org-doc-comparison-review-resolution",
               "mission-doc-comparison-review-resolution",
               "dashboard-doc-comparison-review-resolution",
               %{
                 "schema" => "dashboard_comparison_review_resolution.v1",
                 "source_request_event_id" => request_event.dashboard_lifecycle_event_id,
                 "disposition" => "review_completed",
                 "resolution_reason" => "Reviewed by mission analyst",
                 "selected_placement_id" => "placement-1",
                 "affected_placement_ids" => ["placement-1"]
               },
               actor_id: "user-resolver",
               occurred_at: ~U[2026-06-24 12:30:00.000000Z]
             )

    assert resolution_event.event_type == :comparison_review_resolved
    assert resolution_event.dashboard_version == Document.version(persisted)
    assert resolution_event.previous_lifecycle_state == "active"
    assert resolution_event.current_lifecycle_state == "active"
    assert resolution_event.actor_id == "user-resolver"
    assert resolution_event.occurred_at == ~U[2026-06-24 12:30:00.000000Z]
    assert resolution_event.payload["schema"] == "dashboard_comparison_review_resolution.v1"
    assert resolution_event.payload["request_kind"] == "comparison_open_findings_review"

    assert resolution_event.payload["source_request_event_id"] ==
             request_event.dashboard_lifecycle_event_id

    assert resolution_event.payload["disposition"] == "review_completed"
    assert resolution_event.payload["resolution_reason"] == "Reviewed by mission analyst"
    assert resolution_event.payload["selected_placement_id"] == "placement-1"
    assert resolution_event.payload["affected_placement_ids"] == ["placement-1"]
    assert resolution_event.payload["source_open_count"] == 2
    assert resolution_event.payload["source_open_placement_ids"] == ["placement-1", "placement-2"]
    assert resolution_event.payload["source_scope_kind"] == "transport"
    assert resolution_event.payload["source_scope_ids"] == ["transport-alpha", "transport-beta"]
    assert resolution_event.payload["source_contact_ids"] == ["contact-alpha", "contact-beta"]
    assert resolution_event.payload["source_resource_ids"] == ["transport-alpha"]
    assert resolution_event.payload["source_transport_ids"] == ["transport-alpha"]
    assert resolution_event.payload["source_endpoint_ids"] == ["endpoint-alpha"]
    assert resolution_event.payload["source_ground_station_ids"] == ["dss-14"]
    assert resolution_event.payload["source_scope_link_ids"] == ["link-alpha"]

    assert resolution_event.payload["source_bulk_decision_actionable_count"] == 1

    assert resolution_event.payload["source_bulk_decision_actionable_placement_ids"] == [
             "placement-1"
           ]

    assert resolution_event.payload["source_bulk_decision_skipped_count"] == 1

    assert resolution_event.payload["source_bulk_decision_skipped_placement_ids"] == [
             "placement-2"
           ]

    assert resolution_event.payload["source_bulk_decision_skipped_reasons"] == [
             "missing_observation_identity"
           ]

    assert resolution_event.payload["workflow_intent"] == request_event.payload["workflow_intent"]
    assert resolution_event.payload["open_findings"] == request_event.payload["open_findings"]

    assert [
             %LifecycleEvent{event_type: :comparison_review_requested},
             %LifecycleEvent{event_type: :comparison_review_resolved}
           ] =
             Dashboards.list_lifecycle_events(
               "org-doc-comparison-review-resolution",
               "mission-doc-comparison-review-resolution",
               "dashboard-doc-comparison-review-resolution"
             )

    assert {:error, :comparison_review_already_resolved} =
             Dashboards.record_dashboard_comparison_review_resolution(
               "org-doc-comparison-review-resolution",
               "mission-doc-comparison-review-resolution",
               "dashboard-doc-comparison-review-resolution",
               %{"source_request_event_id" => request_event.dashboard_lifecycle_event_id}
             )

    assert {:error, :comparison_review_request_not_found} =
             Dashboards.record_dashboard_comparison_review_resolution(
               "org-doc-comparison-review-resolution",
               "mission-doc-comparison-review-resolution",
               "dashboard-doc-comparison-review-resolution",
               %{"source_request_event_id" => "missing-request"}
             )
  end
end
