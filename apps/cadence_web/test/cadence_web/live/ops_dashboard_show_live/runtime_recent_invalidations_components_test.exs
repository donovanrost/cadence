defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponents

  test "recent_invalidations renders invalidation attributes and field rows" do
    html =
      render_component(&RuntimeRecentInvalidationsComponents.recent_invalidations/1,
        invalidations: [
          %{
            id: "invalidation-1",
            dashboard_id: "dashboard-1",
            mission_id: "mission-1",
            boundary: "source",
            logical_source: "telemetry",
            realm: "flight",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            replay_run_id: "replay-1",
            observable: "HK.counter",
            lifecycle_action: "published",
            lifecycle_correlation_state: "published",
            lifecycle_correlation_label: "Published v3 invalidated dashboard plan",
            lifecycle_correlation_target_version: "3",
            lifecycle_correlation_source_version: "-",
            source_version: "source-v1",
            document_version: "3",
            context_match: "true",
            context_reason: "matched",
            context_reason_label: "matched",
            refresh_allowed: "true",
            refresh_allowed_reason: "operator_context",
            refresh_allowed_reason_label: "operator_context",
            refresh_reason: "runtime_invalidation",
            refresh_action: "refresh_visible_widgets",
            decision_status: "accepted",
            decision_source: "runtime_health",
            decision_event_id: "decision-1",
            decision_observed_at: "2026-06-26T17:00:00Z",
            affected_placement_count: "2",
            affected_placement_ids: "placement-1,placement-2",
            affected_widget_type_ids: "cadence.value_tile",
            affected_impact_reasons: "source_stale",
            source_cache_evidence_total: "3",
            source_cache_evidence_resolved: "1",
            source_cache_evidence_context_only: "1",
            source_cache_evidence_missing: "1",
            source_cache_evidence_target_ids: "source_health_event:source-health-event-1",
            source_cache_evidence_request_ids: "req-telemetry req-limits",
            source_execution_retryable_count: "3",
            source_execution_actionable_count: "2",
            source_execution_degraded_count: "2",
            source_execution_status_summary:
              "cache_stale:1 source_degraded:1 source_unavailable:1",
            source_execution_runtime_actions: "refresh_source_result:1 wait_for_source_health:2",
            source_execution_degraded_identities:
              "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable",
            source_execution_degraded_actions:
              "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health",
            source_dependency_degraded_count: "1",
            source_dependency_evidence:
              "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale",
            artifacts: "2",
            occurred_at: "2026-06-26T17:00:01Z"
          }
        ],
        dashboard_lifecycle_events: [
          lifecycle_event(
            "dashboard-lifecycle-event-published",
            :published,
            dashboard_version: 3
          )
        ],
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=diagnostics"
      )

    document = LazyHTML.from_fragment(html)

    assert ["source"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-boundary")

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-dashboard")

    assert ["mission-1"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-mission")

    assert ["telemetry"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source")

    assert ["accepted"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-decision-status")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source-cache-evidence-resolved")

    assert ["source_health_event:source-health-event-1"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source-cache-evidence-targets")

    assert ["cache_stale:1 source_degraded:1 source_unavailable:1"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source-execution-statuses")

    assert ["refresh_source_result:1 wait_for_source_health:2"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source-execution-actions")

    assert [
             "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"
           ] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute(
               "data-runtime-invalidation-source-execution-degraded-identities"
             )

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source-dependency-degraded")

    assert [
             "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
           ] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-source-dependency-evidence")

    assert ["published"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-lifecycle-correlation-state")

    assert ["Published v3 invalidated dashboard plan"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-lifecycle-correlation-label")

    assert ["dashboard-lifecycle-event-published"] =
             document
             |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
             |> LazyHTML.attribute("data-runtime-invalidation-activity-event-id")

    activity_link =
      document
      |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
      |> LazyHTML.attribute("data-runtime-invalidation-activity-link")
      |> List.first()

    assert activity_link_path(activity_link) == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert activity_link_query(activity_link) == %{
             "activity_event" => "dashboard-lifecycle-event-published",
             "activity_filter" => "version_changes",
             "panel" => "versions"
           }

    assert [activity_link] ==
             document
             |> LazyHTML.query("[data-runtime-invalidation-activity-link-action]")
             |> LazyHTML.attribute("href")

    admin_decision_link =
      document
      |> LazyHTML.query("#dashboard-runtime-invalidation-invalidation-1")
      |> LazyHTML.attribute("data-runtime-invalidation-admin-decision-link")
      |> List.first()

    assert admin_decision_link_path(admin_decision_link) == "/admin/runtime"

    assert admin_decision_link_query(admin_decision_link) == %{
             "affected_placement_id" => "placement-1",
             "boundary" => "source",
             "context_reason" => "matched",
             "dashboard_id" => "dashboard-1",
             "decision" => "decision-1",
             "mission_id" => "mission-1",
             "replay_run_id" => "replay-1"
           }

    assert [admin_decision_link] ==
             document
             |> LazyHTML.query("[data-runtime-invalidation-admin-decision-link-action]")
             |> LazyHTML.attribute("href")

    assert "HK.counter" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Observable"]))
             |> selected_text()

    assert "Published v3 invalidated dashboard plan" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Lifecycle"]))
             |> selected_text()

    assert "placement-1,placement-2" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Placements"]))
             |> selected_text()

    assert "total:3 resolved:1 context:1 missing:1" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source cache evidence"]))
             |> selected_text()

    assert "source_health_event:source-health-event-1" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source cache evidence targets"]))
             |> selected_text()

    assert "req-telemetry req-limits" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source cache evidence requests"]))
             |> selected_text()

    assert "cache_stale:1 source_degraded:1 source_unavailable:1" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source execution"]))
             |> selected_text()

    assert "refresh_source_result:1 wait_for_source_health:2" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source execution actions"]))
             |> selected_text()

    assert "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source execution degraded"]))
             |> selected_text()

    assert "1" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source dependency degraded"]))
             |> selected_text()

    assert "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale" =
             document
             |> LazyHTML.query(~s([data-invalidation-field="Source dependency evidence"]))
             |> selected_text()
  end

  test "recent_invalidations renders empty state" do
    html =
      render_component(&RuntimeRecentInvalidationsComponents.recent_invalidations/1,
        invalidations: []
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("[data-runtime-invalidation-boundary]")
             |> LazyHTML.attribute("data-runtime-invalidation-boundary")

    assert [] =
             document
             |> LazyHTML.query("[data-runtime-invalidation-admin-decision-link-action]")
             |> LazyHTML.attribute("href")

    assert "No runtime invalidations." =
             document
             |> LazyHTML.query("p")
             |> selected_text()
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end

  defp activity_link_path(link) do
    link
    |> URI.parse()
    |> Map.fetch!(:path)
  end

  defp activity_link_query(link) do
    link
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end

  defp admin_decision_link_path(link) do
    link
    |> URI.parse()
    |> Map.fetch!(:path)
  end

  defp admin_decision_link_query(link) do
    link
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
