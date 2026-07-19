defmodule Cadence.Dashboards.DocumentStoreTest do
  use Cadence.DataCase, async: false

  import Cadence.Dashboards.DocumentStoreFixtures

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Engine,
    LifecycleEvent,
    RuntimeCache,
    Version
  }

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
             Cadence.OperationalEvents.list_events(
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
end
