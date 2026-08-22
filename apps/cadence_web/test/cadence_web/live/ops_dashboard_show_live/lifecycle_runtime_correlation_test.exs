defmodule CadenceWeb.OpsDashboardShowLive.LifecycleRuntimeCorrelationTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.LifecycleRuntimeCorrelation

  test "matches publish lifecycle events to runtime invalidations by action and target version" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        dashboard_version: 3
      )

    invalidation = %{
      id: "invalidation-published",
      lifecycle_action: "published",
      document_version: "3",
      source_version: "-",
      context_match: "true",
      refresh_allowed: "true",
      refresh_action: "refresh_plan",
      context_reason_label: "matched",
      refresh_allowed_reason_label: "refresh allowed"
    }

    assert LifecycleRuntimeCorrelation.activity_event(invalidation, [event]) == event

    assert LifecycleRuntimeCorrelation.activity_event_id(invalidation, [event]) ==
             "dashboard-lifecycle-event-published"

    assert LifecycleRuntimeCorrelation.runtime_impact(event, [invalidation]) == %{
             state: "refresh_allowed",
             label: "Runtime refresh allowed: refresh_plan",
             invalidation_id: "invalidation-published",
             context_match: "true",
             refresh_allowed: "true",
             refresh_action: "refresh_plan",
             context_reason: "matched",
             refresh_reason: "refresh allowed"
           }
  end

  test "matches restore lifecycle events by source and target version" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-reverted",
        :reverted,
        dashboard_version: 9,
        payload: %{"source_version" => 7}
      )

    matching = %{
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

    wrong_source = %{matching | id: "invalidation-wrong", source_version: "6"}

    assert LifecycleRuntimeCorrelation.activity_event(matching, [event]) == event
    assert LifecycleRuntimeCorrelation.activity_event(wrong_source, [event]) == nil

    assert LifecycleRuntimeCorrelation.runtime_impact(event, [wrong_source]).state ==
             "not_observed"

    assert LifecycleRuntimeCorrelation.runtime_impact(event, [matching]) == %{
             state: "context_filtered",
             label: "Runtime invalidation filtered: filtered by realm",
             invalidation_id: "invalidation-revert",
             context_match: "false",
             refresh_allowed: "false",
             refresh_action: "refresh_plan",
             context_reason: "filtered by realm",
             refresh_reason: "stale before current context"
           }
  end

  test "returns not applicable impact for non-version lifecycle events" do
    event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    assert LifecycleRuntimeCorrelation.runtime_impact(event, []).state == "not_applicable"
  end
end
