defmodule CadenceWeb.OpsDashboardShowLive.ActivityViewModelTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel

  test "build returns all lifecycle activity by default" do
    older = lifecycle_event("published-1", :published, occurred_at: ~U[2026-06-24 11:00:00Z])
    newer = lifecycle_event("published-2", :published, occurred_at: ~U[2026-06-24 12:00:00Z])

    model = ActivityViewModel.build([older, newer], nil)

    assert model.mode == :all
    assert model.title == "Activity"
    assert model.filter_value == ""
    assert model.visible_events == [newer, older]
    assert model.total_count == 2
    assert model.open_review_queue == []
    assert model.open_summary.count == 0
    assert model.queue_state == :not_applicable
    assert model.queue_state_value == ""
    assert model.queue_message == nil
  end

  test "build returns an open comparison review work queue" do
    open_request =
      comparison_review_request_event(
        event_id: "request-open",
        occurred_at: ~U[2026-06-24 12:00:00Z],
        placement_ids: ["placement-1"]
      )

    resolved_request =
      comparison_review_request_event(
        event_id: "request-resolved",
        occurred_at: ~U[2026-06-24 12:01:00Z],
        placement_ids: ["placement-2"]
      )

    resolution =
      comparison_review_resolution_event(
        event_id: "resolution-1",
        source_request_event_id: "request-resolved",
        occurred_at: ~U[2026-06-24 12:02:00Z]
      )

    published = lifecycle_event("published-1", :published, occurred_at: ~U[2026-06-24 12:03:00Z])

    events = [open_request, resolved_request, resolution, published]

    model =
      ActivityViewModel.build(events, :open_comparison_reviews,
        open_summary: ComparisonReviewQueue.open_summary(events)
      )

    assert model.mode == :open_comparison_reviews
    assert model.title == "Review Queue"
    assert model.filter_value == "open_comparison_reviews"
    assert model.visible_events == [open_request]
    assert model.total_count == 4
    assert model.open_review_queue == [open_request]
    assert model.open_summary.request_ids == ["request-open"]
    assert model.open_summary.placement_ids == ["placement-1"]
    assert model.queue_state == :open
    assert model.queue_state_value == "open"
    assert model.queue_message == nil
  end

  test "build can use an already materialized open comparison review queue" do
    queue_request =
      comparison_review_request_event(
        event_id: "request-from-queue",
        occurred_at: ~U[2026-06-24 12:00:00Z],
        placement_ids: ["placement-9"]
      )

    published = lifecycle_event("published-1", :published, occurred_at: ~U[2026-06-24 12:03:00Z])

    model =
      ActivityViewModel.build([published], :open_comparison_reviews,
        open_summary: %{
          count: 1,
          count_text: "1",
          requests: [queue_request],
          request_ids: ["request-from-queue"],
          request_ids_attr: "request-from-queue",
          placement_ids: ["placement-9"],
          placements_attr: "placement-9"
        }
      )

    assert model.visible_events == [queue_request]
    assert model.total_count == 1
    assert model.open_review_queue == [queue_request]
    assert model.open_summary.request_ids == ["request-from-queue"]
    assert model.open_summary.placement_ids == ["placement-9"]
    assert model.queue_state == :open
  end

  test "build does not derive open comparison review queue from lifecycle events" do
    open_request =
      comparison_review_request_event(
        event_id: "request-open",
        occurred_at: ~U[2026-06-24 12:00:00Z],
        placement_ids: ["placement-1"]
      )

    model = ActivityViewModel.build([open_request], :open_comparison_reviews)

    assert model.visible_events == []
    assert model.open_review_queue == []
    assert model.open_summary == ComparisonReviewQueue.open_summary([])
    assert model.queue_state == :empty
  end

  test "build filters lifecycle activity by supported audit groups" do
    published = lifecycle_event("published-1", :published, occurred_at: ~U[2026-06-24 12:00:00Z])

    review =
      comparison_review_request_event(
        event_id: "review-1",
        occurred_at: ~U[2026-06-24 12:01:00Z]
      )

    health =
      lifecycle_event(
        "health-1",
        :health_snapshot_captured,
        occurred_at: ~U[2026-06-24 12:02:00Z]
      )

    readiness =
      lifecycle_event(
        "readiness-1",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-24 12:03:00Z]
      )

    events = [published, review, health, readiness]

    health_model = ActivityViewModel.build(events, "health_snapshots")
    assert health_model.mode == :health_snapshots
    assert health_model.title == "Health Snapshots"
    assert health_model.filter_value == "health_snapshots"
    assert health_model.filter_label == "Health snapshots"
    assert health_model.visible_events == [health]
    assert health_model.total_count == 4

    readiness_model = ActivityViewModel.build(events, "publish_readiness")
    assert readiness_model.mode == :publish_readiness
    assert readiness_model.title == "Publish Readiness"
    assert readiness_model.filter_value == "publish_readiness"
    assert readiness_model.filter_label == "Publish readiness"
    assert readiness_model.visible_events == [readiness]
    assert readiness_model.total_count == 4

    review_model = ActivityViewModel.build(events, :comparison_reviews)
    assert review_model.mode == :comparison_reviews
    assert review_model.visible_events == [review]

    version_model = ActivityViewModel.build(events, :version_changes)
    assert version_model.mode == :version_changes
    assert version_model.visible_events == [published]
  end

  test "normalize_filter rejects unsupported values" do
    assert ActivityViewModel.normalize_filter("health_snapshots") == :health_snapshots
    assert ActivityViewModel.normalize_filter("publish_readiness") == :publish_readiness
    assert ActivityViewModel.normalize_filter(:all) == nil
    assert ActivityViewModel.normalize_filter("unknown") == nil
  end

  test "build marks focused review queues empty when all requests are resolved" do
    request =
      comparison_review_request_event(
        event_id: "request-resolved",
        occurred_at: ~U[2026-06-24 12:01:00Z],
        placement_ids: ["placement-2"]
      )

    resolution =
      comparison_review_resolution_event(
        event_id: "resolution-1",
        source_request_event_id: "request-resolved",
        occurred_at: ~U[2026-06-24 12:02:00Z]
      )

    events = [request, resolution]

    model =
      ActivityViewModel.build(events, :open_comparison_reviews,
        open_summary: ComparisonReviewQueue.open_summary(events)
      )

    assert model.visible_events == []
    assert model.open_review_queue == []
    assert model.queue_state == :empty
    assert model.queue_state_value == "empty"
    assert model.queue_message == "No open comparison reviews."
  end

  test "build marks selected placements stale when they leave the open queue" do
    open_request =
      comparison_review_request_event(
        event_id: "request-open",
        occurred_at: ~U[2026-06-24 12:00:00Z],
        placement_ids: ["placement-current"]
      )

    events = [open_request]

    model =
      ActivityViewModel.build(events, :open_comparison_reviews,
        open_summary: ComparisonReviewQueue.open_summary(events),
        selected_placement_id: "placement-stale"
      )

    assert model.visible_events == [open_request]
    assert model.open_review_queue == [open_request]
    assert model.queue_state == :selection_stale
    assert model.queue_state_value == "selection_stale"

    assert model.queue_message ==
             "Selected review placement is no longer part of the open review queue."
  end
end
