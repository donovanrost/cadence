defmodule Cadence.Dashboards.DocumentStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Engine,
    LifecycleEvent,
    RuntimeCache,
    RuntimeInvalidation,
    ValidationResult,
    Version
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.Schemas.{DashboardVersionRow, OpsDashboardRow}
  alias Cadence.Repo

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  setup do
    RuntimeCache.reset()
    on_exit(fn -> RuntimeCache.reset() end)
    :ok
  end

  test "persists and fetches canonical dashboard documents" do
    persist_mission_scope("org-doc-store", "mission-doc-store")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-store", "mission-doc-store", "dashboard-doc-store")

    assert {:ok, %Document{} = persisted} = Dashboards.persist_document("org-doc-store", document)
    assert Document.version(persisted) == 1

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries("org-doc-store", "mission-doc-store")

    assert summary.document_version == 1
    assert summary.latest_version == 1
    assert summary.draft_version == 1
    assert summary.published_version == nil
    assert summary.lifecycle_state == "active"

    assert {:ok, %Document{} = fetched} =
             Dashboards.fetch_document(
               "org-doc-store",
               "mission-doc-store",
               "dashboard-doc-store"
             )

    assert fetched == persisted
    assert fetched.placements == document.placements

    assert [%Version{} = version] =
             Dashboards.list_versions("org-doc-store", "mission-doc-store", "dashboard-doc-store")

    assert version.version == 1
    assert version.snapshot_kind == :draft_save
    assert version.document == persisted
    assert version.parent_version == nil
    assert version.based_on_version == nil

    assert {:ok, %Version{} = fetched_version} =
             Dashboards.fetch_version(
               "org-doc-store",
               "mission-doc-store",
               "dashboard-doc-store",
               1
             )

    assert fetched_version.document == persisted

    result = Engine.plan(resolve_request(fetched), runtime_cache: false)

    assert result.dashboard_id == "dashboard-doc-store"
    assert result.plan_metadata.source_request_count == 2
  end

  test "updates canonical documents with a new document version" do
    persist_mission_scope("org-doc-update", "mission-doc-update")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-update", "mission-doc-update", "dashboard-doc-update")

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-update", document)

    updated_document = %Document{persisted | name: "Updated Power Latest"}

    assert {:ok, %Document{} = updated} =
             Dashboards.update_document(
               "org-doc-update",
               "mission-doc-update",
               "dashboard-doc-update",
               updated_document
             )

    assert updated.name == "Updated Power Latest"
    assert Document.version(updated) == 2

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries("org-doc-update", "mission-doc-update")

    assert summary.document_version == 2
    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == nil
    assert summary.lifecycle_state == "active"

    assert {:ok, %Document{} = fetched} =
             Dashboards.fetch_document(
               "org-doc-update",
               "mission-doc-update",
               "dashboard-doc-update"
             )

    assert fetched == updated

    assert [%Version{} = v1, %Version{} = v2] =
             Dashboards.list_versions(
               "org-doc-update",
               "mission-doc-update",
               "dashboard-doc-update"
             )

    assert v1.version == 1
    assert v1.document.name == persisted.name
    assert v2.version == 2
    assert v2.document == updated
    assert v2.parent_version == 1
    assert v2.based_on_version == 1

    assert {:ok, %Version{} = fetched_v1} =
             Dashboards.fetch_version(
               "org-doc-update",
               "mission-doc-update",
               "dashboard-doc-update",
               1
             )

    assert fetched_v1.document.name == persisted.name

    assert {:error, :dashboard_version_not_found} =
             Dashboards.fetch_version(
               "org-doc-update",
               "mission-doc-update",
               "dashboard-doc-update",
               3
             )
  end

  test "fetching a legacy dashboard row writes a migration snapshot once" do
    persist_mission_scope("org-doc-migrate", "mission-doc-migrate")

    legacy_document = %{
      "dashboard_id" => "dashboard-doc-migrate",
      "organization_id" => "org-doc-migrate",
      "mission_id" => "mission-doc-migrate",
      "name" => "Legacy Widgets",
      "grid" => %{"columns" => 12, "row_height_px" => 64, "gap_px" => 8},
      "widgets" => [
        %{
          "widget_id" => "legacy_counter",
          "type" => "value_tile",
          "title" => "Counter",
          "point_id" => "HK.counter",
          "layout" => %{"x" => 0, "y" => 0, "w" => 2, "h" => 2}
        }
      ],
      "metadata" => %{"version" => 1}
    }

    insert_raw_dashboard_row!(
      "org-doc-migrate",
      "mission-doc-migrate",
      "dashboard-doc-migrate",
      legacy_document
    )

    assert {:ok, %Document{} = migrated} =
             Dashboards.fetch_document(
               "org-doc-migrate",
               "mission-doc-migrate",
               "dashboard-doc-migrate"
             )

    assert migrated.schema_version == 1
    assert Document.version(migrated) == 2
    assert [%{placement_id: "legacy_counter"}] = migrated.placements

    assert [%Version{} = original, %Version{} = migration] =
             Dashboards.list_versions(
               "org-doc-migrate",
               "mission-doc-migrate",
               "dashboard-doc-migrate"
             )

    assert original.version == 1
    assert original.snapshot_kind == :draft_save
    assert original.document.placements == []
    assert migration.version == 2
    assert migration.snapshot_kind == :migration
    assert migration.parent_version == 1
    assert migration.based_on_version == 1
    assert migration.document == migrated
    assert migration.change_summary =~ "dashboard_document.v0_to_v1"
    assert migration.change_summary =~ "dashboard_document.legacy_widgets_to_placements"

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries("org-doc-migrate", "mission-doc-migrate")

    assert summary.document_version == 2
    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == nil

    assert {:ok, %Document{} = fetched_again} =
             Dashboards.fetch_document(
               "org-doc-migrate",
               "mission-doc-migrate",
               "dashboard-doc-migrate"
             )

    assert fetched_again == migrated

    assert [_, _] =
             Dashboards.list_versions(
               "org-doc-migrate",
               "mission-doc-migrate",
               "dashboard-doc-migrate"
             )
  end

  test "rejects stale canonical document updates" do
    persist_mission_scope("org-doc-conflict", "mission-doc-conflict")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-conflict", "mission-doc-conflict", "dashboard-doc-conflict")

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-conflict", document)

    first_update = %Document{persisted | name: "First Writer"}

    assert {:ok, %Document{} = current} =
             Dashboards.update_document(
               "org-doc-conflict",
               "mission-doc-conflict",
               "dashboard-doc-conflict",
               first_update
             )

    assert Document.version(current) == 2

    stale_update = %Document{persisted | name: "Stale Writer"}

    assert {:error, {:dashboard_version_conflict, 2}} =
             Dashboards.update_document(
               "org-doc-conflict",
               "mission-doc-conflict",
               "dashboard-doc-conflict",
               stale_update
             )

    assert {:ok, %Document{} = fetched} =
             Dashboards.fetch_document(
               "org-doc-conflict",
               "mission-doc-conflict",
               "dashboard-doc-conflict"
             )

    assert fetched.name == "First Writer"
    assert Document.version(fetched) == 2

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries("org-doc-conflict", "mission-doc-conflict")

    assert summary.document_version == 2
    assert summary.latest_version == 2
    assert summary.draft_version == 2

    assert [%Version{version: 1}, %Version{version: 2}] =
             Dashboards.list_versions(
               "org-doc-conflict",
               "mission-doc-conflict",
               "dashboard-doc-conflict"
             )
  end

  test "publishes the latest canonical document version" do
    persist_mission_scope("org-doc-publish-latest", "mission-doc-publish-latest")

    published_at = ~U[2026-06-19 22:00:00.000000Z]

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-publish-latest",
        "mission-doc-publish-latest",
        "dashboard-doc-publish-latest"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-publish-latest", document)

    assert {:error, :dashboard_not_published} =
             Dashboards.fetch_published_document(
               "org-doc-publish-latest",
               "mission-doc-publish-latest",
               "dashboard-doc-publish-latest"
             )

    attach_runtime_invalidation_telemetry(self())

    assert {:ok, %Version{} = published} =
             Dashboards.publish_document(
               "org-doc-publish-latest",
               "mission-doc-publish-latest",
               "dashboard-doc-publish-latest",
               1,
               expected_version: 1,
               published_at: published_at,
               published_by: "user-publisher"
             )

    assert published.version == 1
    assert published.snapshot_kind == :publish
    assert published.document == persisted

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.boundary == :dashboard_version_changed
    assert metadata.filters.lifecycle_action == :published
    assert metadata.filters.document_version == 1

    assert {:ok, %Document{} = published_document} =
             Dashboards.fetch_published_document(
               "org-doc-publish-latest",
               "mission-doc-publish-latest",
               "dashboard-doc-publish-latest"
             )

    assert published_document == persisted

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries(
               "org-doc-publish-latest",
               "mission-doc-publish-latest"
             )

    assert summary.latest_version == 1
    assert summary.draft_version == nil
    assert summary.published_version == 1
    assert summary.published_at == published_at
    assert summary.published_by == "user-publisher"

    assert [%LifecycleEvent{} = event] =
             Dashboards.list_lifecycle_events(
               "org-doc-publish-latest",
               "mission-doc-publish-latest",
               "dashboard-doc-publish-latest"
             )

    assert event.event_type == :published
    assert event.dashboard_version == 1
    assert event.previous_lifecycle_state == "active"
    assert event.current_lifecycle_state == "active"
    assert event.previous_published_version == nil
    assert event.current_published_version == 1
    assert event.actor_id == "user-publisher"
    assert event.occurred_at == published_at
    assert LifecycleEvent.details(event).current.published_version == 1

    assert [operational_event] =
             Cadence.list_operational_events(
               "org-doc-publish-latest",
               "mission-doc-publish-latest",
               category: :dashboard,
               kind: :dashboard_published,
               source_record_kind: :dashboard_lifecycle_event,
               source_record_id: event.dashboard_lifecycle_event_id
             )

    assert operational_event.event_id ==
             "operational_event:dashboard_lifecycle_event:#{event.dashboard_lifecycle_event_id}"

    assert operational_event.occurred_at == published_at
    assert operational_event.effective_at == published_at
    assert operational_event.actor == %{kind: :user, id: "user-publisher"}
    assert operational_event.subject == %{kind: :dashboard, id: "dashboard-doc-publish-latest"}

    assert operational_event.payload["dashboard_lifecycle_event_id"] ==
             event.dashboard_lifecycle_event_id

    assert operational_event.payload["dashboard_id"] == "dashboard-doc-publish-latest"
    assert operational_event.payload["event_type"] == "published"
    assert operational_event.payload["dashboard_version"] == 1
    assert operational_event.current["published_version"] == 1
    assert operational_event.current["dashboard_version"] == 1

    assert [%Version{} = published_snapshot] =
             Dashboards.list_versions(
               "org-doc-publish-latest",
               "mission-doc-publish-latest",
               "dashboard-doc-publish-latest"
             )

    assert published_snapshot.version == 1
    assert published_snapshot.snapshot_kind == :publish
  end

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
                 "open_count" => 1,
                 "workflow_intent" => %{
                   "schema" => "dashboard_comparison_workflow_intent.v1",
                   "kind" => "bulk_correction_authority_review",
                   "source" => "dashboard_comparison_rollup",
                   "action" => "request_comparison_review",
                   "selection_kind" => "open_comparison_findings",
                   "selection_count" => 1,
                   "placement_ids" => ["placement-1"]
                 },
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "findings" => [%{"placement_id" => "placement-1"}]
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
    assert resolution_event.payload["source_open_count"] == 1
    assert resolution_event.payload["source_open_placement_ids"] == ["placement-1"]

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

  test "publishing an older version keeps the newer draft pointer" do
    persist_mission_scope("org-doc-publish-older", "mission-doc-publish-older")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-publish-older",
        "mission-doc-publish-older",
        "dashboard-doc-publish-older"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-publish-older", document)

    updated_document = %Document{persisted | name: "Newer Draft"}

    assert {:ok, %Document{} = updated} =
             Dashboards.update_document(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older",
               updated_document
             )

    assert Document.version(updated) == 2

    assert {:ok, %Version{} = published} =
             Dashboards.publish_document(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older",
               1,
               expected_version: 2
             )

    assert published.version == 1
    assert published.snapshot_kind == :publish
    assert published.document == persisted

    assert {:ok, %Document{} = latest_document} =
             Dashboards.fetch_document(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older"
             )

    assert latest_document == updated

    assert {:ok, %Document{} = edit_document} =
             Dashboards.fetch_document_for_mode(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older",
               :edit
             )

    assert edit_document == updated

    assert {:ok, %Document{} = published_document} =
             Dashboards.fetch_published_document(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older"
             )

    assert published_document == persisted

    assert {:ok, %Document{} = view_document} =
             Dashboards.fetch_document_for_mode(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older",
               :view
             )

    assert view_document == persisted

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries(
               "org-doc-publish-older",
               "mission-doc-publish-older"
             )

    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == 1

    assert {:ok, %Version{} = latest_published} =
             Dashboards.publish_document(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older",
               2,
               expected_version: 2
             )

    assert latest_published.version == 2
    assert latest_published.snapshot_kind == :publish

    assert [%Dashboards.DashboardSummary{} = updated_summary] =
             Dashboards.list_dashboard_summaries(
               "org-doc-publish-older",
               "mission-doc-publish-older"
             )

    assert updated_summary.latest_version == 2
    assert updated_summary.draft_version == nil
    assert updated_summary.published_version == 2

    assert [%Version{} = v1, %Version{} = v2] =
             Dashboards.list_versions(
               "org-doc-publish-older",
               "mission-doc-publish-older",
               "dashboard-doc-publish-older"
             )

    assert v1.snapshot_kind == :publish
    assert v2.snapshot_kind == :publish
  end

  test "restores an older version as a new draft" do
    persist_mission_scope("org-doc-revert", "mission-doc-revert")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-revert", "mission-doc-revert", "dashboard-doc-revert")
      |> then(fn %Document{} = document -> %Document{document | name: "Original Draft"} end)

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-revert", document)

    updated_document = %Document{persisted | name: "Published Draft"}

    assert {:ok, %Document{} = updated} =
             Dashboards.update_document(
               "org-doc-revert",
               "mission-doc-revert",
               "dashboard-doc-revert",
               updated_document,
               expected_version: 1
             )

    assert Document.version(updated) == 2

    assert {:ok, %Version{} = published} =
             Dashboards.publish_document(
               "org-doc-revert",
               "mission-doc-revert",
               "dashboard-doc-revert",
               2,
               expected_version: 2
             )

    assert published.version == 2

    attach_runtime_invalidation_telemetry(self())

    assert {:ok, %Version{} = reverted} =
             Dashboards.revert_document(
               "org-doc-revert",
               "mission-doc-revert",
               "dashboard-doc-revert",
               1,
               expected_version: 2,
               created_by: "user-reverter",
               occurred_at: ~U[2026-06-19 23:10:00.000000Z]
             )

    assert reverted.version == 3
    assert reverted.snapshot_kind == :revert
    assert reverted.parent_version == 2
    assert reverted.based_on_version == 1
    assert reverted.created_by == "user-reverter"
    assert reverted.change_summary == "Restored version 1 as draft"
    assert reverted.document.name == "Original Draft"
    assert Document.version(reverted.document) == 3

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.boundary == :dashboard_version_changed
    assert metadata.filters.lifecycle_action == :reverted
    assert metadata.filters.document_version == 3
    assert metadata.filters.source_version == 1

    assert {:ok, %Document{} = latest_document} =
             Dashboards.fetch_document(
               "org-doc-revert",
               "mission-doc-revert",
               "dashboard-doc-revert"
             )

    assert latest_document.name == "Original Draft"
    assert Document.version(latest_document) == 3

    assert {:ok, %Document{} = published_document} =
             Dashboards.fetch_published_document(
               "org-doc-revert",
               "mission-doc-revert",
               "dashboard-doc-revert"
             )

    assert published_document.name == "Published Draft"
    assert Document.version(published_document) == 2

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries("org-doc-revert", "mission-doc-revert")

    assert summary.latest_version == 3
    assert summary.draft_version == 3
    assert summary.published_version == 2

    assert [%Version{version: 1}, %Version{version: 2}, %Version{version: 3} = v3] =
             Dashboards.list_versions(
               "org-doc-revert",
               "mission-doc-revert",
               "dashboard-doc-revert"
             )

    assert v3.snapshot_kind == :revert
    assert v3.based_on_version == 1

    events =
      Dashboards.list_lifecycle_events(
        "org-doc-revert",
        "mission-doc-revert",
        "dashboard-doc-revert"
      )

    assert Enum.any?(events, &match?(%LifecycleEvent{event_type: :published}, &1))
    assert %LifecycleEvent{} = event = Enum.find(events, &(&1.event_type == :reverted))

    assert event.event_type == :reverted
    assert event.dashboard_version == 3
    assert event.previous_published_version == 2
    assert event.current_published_version == 2
    assert event.actor_id == "user-reverter"
    assert event.occurred_at == ~U[2026-06-19 23:10:00.000000Z]
    assert LifecycleEvent.source_version(event) == 1
    assert LifecycleEvent.reverted_version(event) == 3
  end

  test "rejects stale and missing publish targets" do
    persist_mission_scope("org-doc-publish-conflict", "mission-doc-publish-conflict")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-publish-conflict",
        "mission-doc-publish-conflict",
        "dashboard-doc-publish-conflict"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-publish-conflict", document)

    assert {:ok, %Document{} = updated} =
             Dashboards.update_document(
               "org-doc-publish-conflict",
               "mission-doc-publish-conflict",
               "dashboard-doc-publish-conflict",
               %Document{persisted | name: "Current Draft"}
             )

    assert Document.version(updated) == 2

    assert {:error, {:dashboard_version_conflict, 2}} =
             Dashboards.publish_document(
               "org-doc-publish-conflict",
               "mission-doc-publish-conflict",
               "dashboard-doc-publish-conflict",
               2,
               expected_version: 1
             )

    assert {:error, :dashboard_version_not_found} =
             Dashboards.publish_document(
               "org-doc-publish-conflict",
               "mission-doc-publish-conflict",
               "dashboard-doc-publish-conflict",
               3,
               expected_version: 2
             )

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries(
               "org-doc-publish-conflict",
               "mission-doc-publish-conflict"
             )

    assert summary.latest_version == 2
    assert summary.draft_version == 2
    assert summary.published_version == nil

    assert [] =
             Dashboards.list_lifecycle_events(
               "org-doc-publish-conflict",
               "mission-doc-publish-conflict",
               "dashboard-doc-publish-conflict"
             )
  end

  test "lists dashboard summaries from canonical documents" do
    persist_mission_scope("org-doc-summary", "mission-doc-summary")

    empty_document = %Document{
      organization_id: "org-doc-summary",
      mission_id: "mission-doc-summary",
      dashboard_id: "dashboard-doc-summary-empty",
      name: "Empty"
    }

    widget_document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-summary", "mission-doc-summary", "dashboard-doc-summary-widget")
      |> then(fn %Document{} = document -> %Document{document | name: "Battery"} end)

    assert {:ok, %Document{} = empty_persisted} =
             Dashboards.persist_document("org-doc-summary", empty_document)

    assert {:ok, %Document{} = widget_persisted} =
             Dashboards.persist_document("org-doc-summary", widget_document)

    assert [
             %Dashboards.DashboardSummary{} = widget_summary,
             %Dashboards.DashboardSummary{} = empty_summary
           ] =
             Dashboards.list_dashboard_summaries("org-doc-summary", "mission-doc-summary")

    assert widget_summary.dashboard_id == widget_persisted.dashboard_id
    assert widget_summary.name == "Battery"
    assert widget_summary.widget_count == length(widget_persisted.placements)
    assert widget_summary.document_version == 1
    assert widget_summary.latest_version == 1
    assert widget_summary.draft_version == 1
    assert widget_summary.published_version == nil
    assert widget_summary.lifecycle_state == "active"

    assert empty_summary.dashboard_id == empty_persisted.dashboard_id
    assert empty_summary.name == "Empty"
    assert empty_summary.widget_count == 0
    assert empty_summary.document_version == 1
    assert empty_summary.latest_version == 1
    assert empty_summary.draft_version == 1
    assert empty_summary.published_version == nil
    assert empty_summary.lifecycle_state == "active"
  end

  test "archives and restores canonical dashboards" do
    persist_mission_scope("org-doc-archive", "mission-doc-archive")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-archive", "mission-doc-archive", "dashboard-doc-archive")

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-archive", document)

    attach_runtime_invalidation_telemetry(self())

    assert :ok =
             Dashboards.archive_document(
               "org-doc-archive",
               "mission-doc-archive",
               "dashboard-doc-archive",
               actor_id: "user-archiver",
               occurred_at: ~U[2026-06-19 23:00:00.000000Z]
             )

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.boundary == :dashboard_version_changed
    assert metadata.filters.lifecycle_action == :archived
    assert metadata.filters.document_version == 1

    assert [] = Dashboards.list_dashboard_summaries("org-doc-archive", "mission-doc-archive")

    assert [%Dashboards.DashboardSummary{} = archived_summary] =
             Dashboards.list_archived_dashboard_summaries(
               "org-doc-archive",
               "mission-doc-archive"
             )

    assert archived_summary.dashboard_id == persisted.dashboard_id
    assert archived_summary.lifecycle_state == "archived"

    assert {:error, :dashboard_archived} =
             Dashboards.fetch_document_for_mode(
               "org-doc-archive",
               "mission-doc-archive",
               "dashboard-doc-archive",
               :edit
             )

    assert {:error, :dashboard_archived} =
             Dashboards.update_document(
               "org-doc-archive",
               "mission-doc-archive",
               "dashboard-doc-archive",
               %Document{persisted | name: "Archived Edit"},
               expected_version: 1
             )

    assert :ok =
             Dashboards.restore_document(
               "org-doc-archive",
               "mission-doc-archive",
               "dashboard-doc-archive",
               actor_id: "user-restorer",
               occurred_at: ~U[2026-06-19 23:05:00.000000Z]
             )

    assert_receive {:runtime_invalidation_telemetry, _event, _measurements, metadata}
    assert metadata.boundary == :dashboard_version_changed
    assert metadata.filters.lifecycle_action == :restored
    assert metadata.filters.document_version == 1

    assert [%Dashboards.DashboardSummary{} = active_summary] =
             Dashboards.list_dashboard_summaries("org-doc-archive", "mission-doc-archive")

    assert active_summary.dashboard_id == persisted.dashboard_id
    assert active_summary.lifecycle_state == "active"

    assert [] =
             Dashboards.list_archived_dashboard_summaries(
               "org-doc-archive",
               "mission-doc-archive"
             )

    assert [%LifecycleEvent{} = archived, %LifecycleEvent{} = restored] =
             Dashboards.list_lifecycle_events(
               "org-doc-archive",
               "mission-doc-archive",
               "dashboard-doc-archive"
             )

    assert archived.event_type == :archived
    assert archived.dashboard_version == 1
    assert archived.previous_lifecycle_state == "active"
    assert archived.current_lifecycle_state == "archived"
    assert archived.actor_id == "user-archiver"
    assert archived.occurred_at == ~U[2026-06-19 23:00:00.000000Z]
    assert LifecycleEvent.details(archived).previous.lifecycle_state == "active"
    assert LifecycleEvent.details(archived).current.lifecycle_state == "archived"

    assert restored.event_type == :restored
    assert restored.dashboard_version == 1
    assert restored.previous_lifecycle_state == "archived"
    assert restored.current_lifecycle_state == "active"
    assert restored.actor_id == "user-restorer"
    assert restored.occurred_at == ~U[2026-06-19 23:05:00.000000Z]
    assert LifecycleEvent.details(restored).previous.lifecycle_state == "archived"
    assert LifecycleEvent.details(restored).current.lifecycle_state == "active"
  end

  test "rejects stale lifecycle archive restore and delete actions" do
    persist_mission_scope("org-doc-lifecycle-conflict", "mission-doc-lifecycle-conflict")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-lifecycle-conflict",
        "mission-doc-lifecycle-conflict",
        "dashboard-doc-lifecycle-conflict"
      )

    assert {:ok, %Document{} = persisted} =
             Dashboards.persist_document("org-doc-lifecycle-conflict", document)

    assert {:ok, %Document{} = updated} =
             Dashboards.update_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict",
               %Document{persisted | name: "Concurrent Draft"},
               expected_version: 1
             )

    assert Document.version(updated) == 2

    assert {:error, {:dashboard_version_conflict, 2}} =
             Dashboards.archive_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict",
               expected_version: 1
             )

    assert [%Dashboards.DashboardSummary{} = active_summary] =
             Dashboards.list_dashboard_summaries(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict"
             )

    assert active_summary.lifecycle_state == "active"
    assert active_summary.latest_version == 2

    assert [] =
             Dashboards.list_lifecycle_events(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict"
             )

    assert :ok =
             Dashboards.archive_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict",
               expected_version: 2
             )

    assert {:error, {:dashboard_version_conflict, 2}} =
             Dashboards.restore_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict",
               expected_version: 1
             )

    assert [] =
             Dashboards.list_dashboard_summaries(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict"
             )

    assert [%Dashboards.DashboardSummary{} = archived_summary] =
             Dashboards.list_archived_dashboard_summaries(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict"
             )

    assert archived_summary.lifecycle_state == "archived"
    assert archived_summary.latest_version == 2

    assert [%LifecycleEvent{event_type: :archived}] =
             Dashboards.list_lifecycle_events(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict"
             )

    assert :ok =
             Dashboards.restore_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict",
               expected_version: 2
             )

    assert {:error, {:dashboard_version_conflict, 2}} =
             Dashboards.delete_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict",
               expected_version: 1
             )

    assert {:ok, %Document{} = fetched} =
             Dashboards.fetch_document(
               "org-doc-lifecycle-conflict",
               "mission-doc-lifecycle-conflict",
               "dashboard-doc-lifecycle-conflict"
             )

    assert fetched.name == "Concurrent Draft"
    assert Document.version(fetched) == 2
  end

  test "document writes invalidate cached dashboard plans" do
    persist_mission_scope("org-doc-cache", "mission-doc-cache")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-cache", "mission-doc-cache", "dashboard-doc-cache")

    assert {:ok, %Document{} = persisted} = Dashboards.persist_document("org-doc-cache", document)
    assert plan_cache_status(persisted) == :miss
    assert plan_cache_status(persisted) == :hit

    updated_document = %Document{persisted | name: "Cache Invalidated"}

    assert {:ok, %Document{} = updated} =
             Dashboards.update_document(
               "org-doc-cache",
               "mission-doc-cache",
               "dashboard-doc-cache",
               updated_document
             )

    assert plan_cache_status(updated) == :miss
    assert plan_cache_status(updated) == :hit

    assert :ok =
             Dashboards.delete_document(
               "org-doc-cache",
               "mission-doc-cache",
               "dashboard-doc-cache",
               expected_version: Document.version(updated)
             )

    assert plan_cache_status(updated) == :miss

    assert {:error, :dashboard_not_found} =
             Dashboards.fetch_document(
               "org-doc-cache",
               "mission-doc-cache",
               "dashboard-doc-cache"
             )
  end

  test "rejects invalid canonical dashboard documents" do
    persist_mission_scope("org-doc-invalid", "mission-doc-invalid")

    invalid =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document("org-doc-invalid", "mission-doc-invalid", "dashboard-doc-invalid")
      |> then(fn %Document{} = document -> %Document{document | name: nil} end)

    assert {:error, {:invalid_dashboard_document, result}} =
             Dashboards.persist_document("org-doc-invalid", invalid)

    refute result.valid?
  end

  test "rejects publish when mission source capabilities cannot satisfy planned requests" do
    persist_mission_scope("org-doc-unready-source", "mission-doc-unready-source")

    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> scope_document(
        "org-doc-unready-source",
        "mission-doc-unready-source",
        "dashboard-doc-unready-source"
      )

    assert {:ok, %Document{}} = Dashboards.persist_document("org-doc-unready-source", document)

    persist_publish_source!(
      "org-doc-unready-source",
      "mission-doc-unready-source",
      :telemetry,
      "unready-telemetry-source",
      "unready-telemetry-binding",
      Cadence.Dashboards.Sources.Telemetry,
      %{latest?: false, range_scan?: true}
    )

    persist_publish_source!(
      "org-doc-unready-source",
      "mission-doc-unready-source",
      :limits,
      "ready-limits-source",
      "ready-limits-binding",
      Cadence.Dashboards.Sources.Limits,
      %{latest_state?: true, event_history?: true, definition_intervals?: true}
    )

    assert {:error, {:invalid_dashboard_document, result}} =
             Dashboards.publish_document(
               "org-doc-unready-source",
               "mission-doc-unready-source",
               "dashboard-doc-unready-source",
               1,
               expected_version: 1
             )

    refute result.valid?

    assert %{
             code: :unready_publish_source_request,
             details: %{
               source_warning_code: :unsupported_source_capability,
               details: details
             }
           } =
             Enum.find(
               result.errors,
               &(&1.details.source_warning_code == :unsupported_source_capability)
             )

    assert details.logical_source == :telemetry
    assert details.requested_sampling == :latest
    assert details.source_binding_id == "unready-telemetry-binding"
    assert details.data_source_id == "unready-telemetry-source"

    assert {:ok, %DataSource{}} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "ready-telemetry-source",
               owner: :cadence,
               kind: :projection,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-doc-unready-source",
               mission_id: "mission-doc-unready-source",
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true}
             })

    assert {:ok, %DataBinding{}} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "unready-telemetry-binding",
               organization_id: "org-doc-unready-source",
               mission_id: "mission-doc-unready-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "ready-telemetry-source",
               dataset: "telemetry",
               priority: 0
             })

    assert %{valid?: true, errors: []} =
             Dashboards.validate_publish_readiness(
               "org-doc-unready-source",
               "mission-doc-unready-source",
               document
             )

    assert {:ok, published} =
             Dashboards.publish_document(
               "org-doc-unready-source",
               "mission-doc-unready-source",
               "dashboard-doc-unready-source",
               1,
               expected_version: 1
             )

    assert published.version == 1

    assert [%Dashboards.DashboardSummary{} = summary] =
             Dashboards.list_dashboard_summaries(
               "org-doc-unready-source",
               "mission-doc-unready-source"
             )

    assert summary.published_version == 1
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp scope_document(%Document{} = document, organization_id, mission_id, dashboard_id) do
    %Document{
      document
      | organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: dashboard_id
    }
  end

  defp persist_publish_source!(
         organization_id,
         mission_id,
         logical_source,
         data_source_id,
         binding_id,
         adapter,
         capabilities
       ) do
    assert {:ok, %DataSource{}} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :projection,
               adapter: adapter,
               organization_id: organization_id,
               mission_id: mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, %DataBinding{}} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: organization_id,
               mission_id: mission_id,
               realm: :flight,
               logical_source: logical_source,
               data_source_id: data_source_id,
               dataset: Atom.to_string(logical_source),
               priority: 0
             })
  end

  defp health_snapshot do
    %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => "dashboard_health_snapshot_abc123",
      "organization_id" => "org-doc-health-snapshot",
      "mission_id" => "mission-doc-health-snapshot",
      "dashboard_id" => "dashboard-doc-health-snapshot",
      "state" => "blocked",
      "severity" => "error",
      "counts" => %{
        "widgets" => 2,
        "ready" => 1,
        "degraded" => 0,
        "stale" => 0,
        "blocked" => 1,
        "affected" => 1
      },
      "placement_ids" => %{
        "affected" => ["blocked-placement"],
        "blocked" => ["blocked-placement"],
        "stale" => [],
        "degraded" => []
      }
    }
  end

  defp insert_raw_dashboard_row!(organization_id, mission_id, dashboard_id, raw_document) do
    encoded_document = JsonDocument.encode(raw_document)

    Repo.insert!(%OpsDashboardRow{
      dashboard_id: dashboard_id,
      organization_id: organization_id,
      mission_id: mission_id,
      name: raw_document["name"],
      description: raw_document["description"],
      document: encoded_document,
      latest_version: 1,
      draft_version: 1,
      lifecycle_state: "active"
    })

    Repo.insert!(%DashboardVersionRow{
      dashboard_version_id: "#{dashboard_id}-version-1",
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id,
      version: 1,
      document: encoded_document,
      snapshot_kind: :draft_save,
      schema_version: 1
    })
  end

  defp plan_cache_status(%Document{} = document) do
    document
    |> resolve_request()
    |> Engine.plan()
    |> get_in([Access.key!(:plan_metadata), Access.key!(:cache), Access.key!(:plan_cache)])
    |> Map.fetch!(:status)
  end

  defp attach_runtime_invalidation_telemetry(test_pid) do
    handler_id = "document-store-runtime-invalidation-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [RuntimeInvalidation.telemetry_event()],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:runtime_invalidation_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp resolve_request(%Document{} = document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{
        placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}
      }
    }
  end
end
