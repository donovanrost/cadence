defmodule CadenceWeb.OpsDashboardShowLive.RuntimeNoRefreshSummaryComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeNoRefreshSummaryComponents

  test "no_refresh_summary renders visible context and refresh fields" do
    html =
      render_component(&RuntimeNoRefreshSummaryComponents.no_refresh_summary/1,
        summary: %{
          visible?: true,
          status: "suppressed",
          context: "matched",
          refresh: "blocked",
          headline: "Runtime invalidation matched the dashboard context but refresh was blocked."
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["suppressed"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-status")

    assert "matched" =
             document
             |> LazyHTML.query(~s([data-no-refresh-field="Context"]))
             |> selected_text()

    assert "blocked" =
             document
             |> LazyHTML.query(~s([data-no-refresh-field="Refresh"]))
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-blocker")
             |> LazyHTML.attribute("id")

    assert [] =
             document
             |> LazyHTML.query("[data-no-refresh-admin-decision-link-action]")
             |> LazyHTML.attribute("href")
  end

  test "no_refresh_summary renders blocker details with fallback display values" do
    html =
      render_component(&RuntimeNoRefreshSummaryComponents.no_refresh_summary/1,
        summary: %{
          visible?: true,
          status: "suppressed",
          context: "matched",
          refresh: "blocked",
          headline: "Runtime invalidation was blocked by the active dashboard boundary.",
          blocker: %{
            dashboard_id: "dashboard-1",
            mission_id: "mission-1",
            boundary: "dashboard_time_context",
            refresh_action: "refresh_source_result",
            logical_source: "telemetry",
            realm: "replay",
            data_source_id: "questdb-replay",
            source_binding_id: "replay-binding",
            decision_source: "runtime_health",
            decision_event_id: "decision-1",
            observable: "",
            replay_run_id: "replay-1",
            lifecycle_action: "historical_data_written",
            context_reason_filter: "scope_mismatch",
            context_reason: "scope_mismatch",
            refresh_reason_filter: "stale_for_context",
            refresh_reason: nil,
            affected_placement_ids: "placement-1,placement-2",
            affected_impact_reasons: "source_context_filtered",
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
              "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
          }
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard_time_context"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-boundary")

    assert ["refresh_source_result"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-refresh-action")

    assert ["telemetry"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-logical-source")

    assert ["replay"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-realm")

    assert ["questdb-replay"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-data-source")

    assert ["replay-binding"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-binding")

    assert ["-"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-observable")

    assert ["historical_data_written"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-lifecycle-action")

    assert ["-"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-refresh")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-cache-evidence-total")

    assert ["source_health_event:source-health-event-1"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-cache-evidence-targets")

    assert ["cache_stale:1 source_degraded:1 source_unavailable:1"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-execution-statuses")

    assert ["refresh_source_result:1 wait_for_source_health:2"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-execution-actions")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-dependency-degraded")

    assert [
             "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
           ] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("data-no-refresh-blocking-source-dependency-evidence")

    assert "refresh_source_result" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Action"]))
             |> selected_text()

    assert "telemetry:replay:questdb-replay:replay-binding" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Identity"]))
             |> selected_text()

    assert "historical_data_written" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Lifecycle"]))
             |> selected_text()

    assert "runtime_health" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Decision source"]))
             |> selected_text()

    assert "placement-1,placement-2" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Placements"]))
             |> selected_text()

    assert "total:3 resolved:1 context:1 missing:1" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Source cache evidence"]))
             |> selected_text()

    assert "source_health_event:source-health-event-1" =
             document
             |> LazyHTML.query(
               ~s([data-no-refresh-blocker-field="Source cache evidence targets"])
             )
             |> selected_text()

    assert "req-telemetry req-limits" =
             document
             |> LazyHTML.query(
               ~s([data-no-refresh-blocker-field="Source cache evidence requests"])
             )
             |> selected_text()

    assert "cache_stale:1 source_degraded:1 source_unavailable:1" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Source execution"]))
             |> selected_text()

    assert "refresh_source_result:1 wait_for_source_health:2" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Source execution actions"]))
             |> selected_text()

    assert "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Source execution degraded"]))
             |> selected_text()

    assert "1" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Source dependency degraded"]))
             |> selected_text()

    assert "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale" =
             document
             |> LazyHTML.query(~s([data-no-refresh-blocker-field="Source dependency evidence"]))
             |> selected_text()

    admin_decision_link =
      document
      |> LazyHTML.query("#dashboard-no-refresh-summary")
      |> LazyHTML.attribute("data-no-refresh-blocking-admin-decision-link")
      |> List.first()

    assert admin_decision_link_path(admin_decision_link) == "/admin/runtime"

    assert admin_decision_link_query(admin_decision_link) == %{
             "affected_placement_id" => "placement-1",
             "boundary" => "dashboard_time_context",
             "context_reason" => "scope_mismatch",
             "dashboard_id" => "dashboard-1",
             "decision" => "decision-1",
             "mission_id" => "mission-1",
             "replay_run_id" => "replay-1"
           }

    assert [^admin_decision_link] =
             document
             |> LazyHTML.query("[data-no-refresh-admin-decision-link-action]")
             |> LazyHTML.attribute("href")
  end

  test "no_refresh_summary renders nothing when hidden" do
    html =
      render_component(&RuntimeNoRefreshSummaryComponents.no_refresh_summary/1,
        summary: %{visible?: false}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-no-refresh-summary")
             |> LazyHTML.attribute("id")
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
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
