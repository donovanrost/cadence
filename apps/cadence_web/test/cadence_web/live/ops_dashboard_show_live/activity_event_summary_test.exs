defmodule CadenceWeb.OpsDashboardShowLive.ActivityEventSummaryTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary

  test "build returns no rendered summary without a selected event id" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :published)

    assert %{
             render?: false,
             runtime_impact: %{state: "not_applicable"}
           } = ActivityEventSummary.build([event], nil, [event], %{filter_value: ""})

    assert %{
             render?: false,
             runtime_impact: %{state: "not_applicable"}
           } = ActivityEventSummary.build([event], "", [event], %{filter_value: ""})
  end

  test "build summarizes a visible selected lifecycle event" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-1",
        :reverted,
        actor_id: "operator-1",
        dashboard_version: 7,
        occurred_at: ~U[2026-06-24 12:03:00Z],
        payload: %{
          "source_version" => 5,
          "reverted_version" => 8
        }
      )
      |> Map.put(:previous_published_version, 5)
      |> Map.put(:current_published_version, 6)

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-1",
        [event],
        %{filter_value: "version_changes"}
      )

    assert %{
             render?: true,
             event: ^event,
             event_id: "dashboard-lifecycle-event-1",
             found?: true,
             found_text: "true",
             visible?: true,
             visible_text: "true",
             filter_value: "version_changes",
             event_type_text: "reverted",
             title: "Restored as draft",
             version_text: "v7",
             filter_state: nil,
             filter_state_text: nil,
             visibility_class: nil
           } = summary

    assert [
             %{label: "Event", value: "dashboard-lifecycle-event-1"},
             %{label: "Occurred", value: "2026-06-24 12:03:00 UTC"},
             %{label: "Actor", value: "operator-1"},
             %{label: "Published", value: "v5 -> v6"},
             %{label: "Source", value: "v5"},
             %{label: "New draft", value: "v8"},
             %{label: "Runtime", value: "No runtime invalidation observed"}
           ] = Enum.map(summary.fields, &Map.take(&1, [:label, :value]))
  end

  test "build marks selected events hidden when filtered out" do
    selected_event = lifecycle_event("dashboard-lifecycle-event-published", :published)
    visible_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    summary =
      ActivityEventSummary.build(
        [selected_event, visible_event],
        "dashboard-lifecycle-event-published",
        [visible_event],
        %{filter_value: "health_snapshots"}
      )

    assert summary.found? == true
    assert summary.found_text == "true"
    assert summary.visible? == false
    assert summary.visible_text == "false"
    assert summary.event_type_text == "published"
    assert summary.title == "Published"
    assert summary.filter_state == :hidden
    assert summary.filter_state_text == "hidden"
    assert summary.visibility_class == "border-warning/40 bg-warning/10"
  end

  test "build correlates selected lifecycle events to runtime invalidations" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        dashboard_version: 3
      )

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-published",
        [event],
        %{filter_value: "version_changes"},
        [
          %{
            id: "invalidation-1",
            lifecycle_action: "published",
            document_version: "3",
            source_version: "-",
            context_match: "true",
            refresh_allowed: "true",
            refresh_action: "refresh_plan",
            context_reason_label: "matched",
            refresh_allowed_reason_label: "refresh allowed"
          }
        ]
      )

    assert summary.runtime_impact == %{
             state: "refresh_allowed",
             label: "Runtime refresh allowed: refresh_plan",
             invalidation_id: "invalidation-1",
             context_match: "true",
             refresh_allowed: "true",
             refresh_action: "refresh_plan",
             context_reason: "matched",
             refresh_reason: "refresh allowed"
           }

    assert %{label: "Runtime", value: "Runtime refresh allowed: refresh_plan"} in Enum.map(
             summary.fields,
             &Map.take(&1, [:label, :value])
           )
  end

  test "build marks missing selected events unavailable" do
    event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-missing",
        [event],
        %{filter_value: ""}
      )

    assert summary.event == nil
    assert summary.found? == false
    assert summary.found_text == "false"
    assert summary.visible? == false
    assert summary.visible_text == "false"
    assert summary.event_type_text == nil
    assert summary.title == "Activity event unavailable"
    assert summary.version_text == nil
    assert summary.filter_state == :missing
    assert summary.filter_state_text == "missing"
    assert summary.visibility_class == "border-error/40 bg-error/10"
    assert summary.fields == []
  end

  test "rows summarize visible activity events for list rendering" do
    selected_event =
      lifecycle_event(
        "dashboard-lifecycle-event-selected",
        :reverted,
        dashboard_version: 9,
        actor_id: "operator-1",
        occurred_at: ~U[2026-06-24 12:04:00Z],
        payload: %{
          "source_version" => 7,
          "reverted_version" => 10
        }
      )
      |> Map.put(:previous_published_version, 6)
      |> Map.put(:current_published_version, 7)

    other_event =
      lifecycle_event(
        "dashboard-lifecycle-event-other",
        :health_snapshot_captured,
        dashboard_version: 8
      )

    [selected_row, other_row] =
      ActivityEventSummary.rows(
        [selected_event, other_event],
        "dashboard-lifecycle-event-selected"
      )

    assert %{
             event: ^selected_event,
             event_id: "dashboard-lifecycle-event-selected",
             event_type: :reverted,
             event_type_text: "reverted",
             title: "Restored as draft",
             version_text: "v9",
             selected?: true,
             selected_text: "true",
             source_version_text: "7",
             reverted_version_text: "10",
             class: ["border-l-2 bg-base-100/40 px-2 py-2", "border-info bg-info/10"]
           } = selected_row

    assert [
             %{label: "Occurred", value: "2026-06-24 12:04:00 UTC"},
             %{label: "Actor", value: "operator-1"},
             %{label: "Published", value: "v6 -> v7"},
             %{label: "Source", value: "v7"},
             %{label: "New draft", value: "v10"},
             %{label: "Runtime", value: "No runtime invalidation observed"}
           ] = Enum.map(selected_row.fields, &Map.take(&1, [:label, :value]))

    assert other_row.selected? == false
    assert other_row.selected_text == "false"
    assert other_row.class == ["border-l-2 bg-base-100/40 px-2 py-2", "border-primary/60"]
  end

  test "rows report filtered or missing runtime invalidation impact for lifecycle events" do
    reverted =
      lifecycle_event(
        "dashboard-lifecycle-event-reverted",
        :reverted,
        dashboard_version: 9,
        payload: %{"source_version" => 7}
      )

    [row] =
      ActivityEventSummary.rows(
        [reverted],
        nil,
        [
          %{
            id: "invalidation-revert",
            lifecycle_action: "reverted",
            document_version: "9",
            source_version: "7",
            context_match: "false",
            refresh_allowed: "false",
            refresh_action: "refresh_plan",
            context_reason_label: "filtered by realm",
            refresh_allowed_reason_label: "stale before current context"
          }
        ]
      )

    assert row.runtime_impact == %{
             state: "context_filtered",
             label: "Runtime invalidation filtered: filtered by realm",
             invalidation_id: "invalidation-revert",
             context_match: "false",
             refresh_allowed: "false",
             refresh_action: "refresh_plan",
             context_reason: "filtered by realm",
             refresh_reason: "stale before current context"
           }

    [missing_row] = ActivityEventSummary.rows([reverted], nil, [])

    assert missing_row.runtime_impact.state == "not_observed"
    assert missing_row.runtime_impact.label == "No runtime invalidation observed"
  end

  test "label exposes lifecycle event display names" do
    assert ActivityEventSummary.label(:comparison_review_requested) ==
             "Comparison review requested"

    assert ActivityEventSummary.label(:health_snapshot_captured) == "Health snapshot captured"
    assert ActivityEventSummary.label(:publish_readiness_checked) == "Publish readiness checked"
  end
end
