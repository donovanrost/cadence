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

    vue = no_refresh_vue(html)
    summary = vue.props["summary"]
    section_attributes = summary["section"]["attributes"]

    assert section_attributes["data-no-refresh-status"] == "suppressed"

    assert field_value(summary["fields"]["rows"], "data-no-refresh-field", "Context") ==
             "matched"

    assert field_value(summary["fields"]["rows"], "data-no-refresh-field", "Refresh") ==
             "blocked"

    assert summary["blocker"] == nil
    assert summary["admin_action"] == nil

    assert summary["section"] == %{
             "id" => "dashboard-no-refresh-summary",
             "class" => "border border-warning/30 bg-warning/10 px-3 py-2 text-sm",
             "attributes" => section_attributes
           }

    assert summary["heading"] == %{"class" => "hud-label", "text" => "Why no refresh?"}

    assert summary["headline"] == %{
             "class" => "mt-1 text-base-content",
             "text" =>
               "Runtime invalidation matched the dashboard context but refresh was blocked."
           }

    assert summary["fields"]["class"] ==
             "mt-2 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs"

    assert Enum.map(summary["fields"]["rows"], &field_contract(&1, "data-no-refresh-field")) ==
             [
               {"context", "Context", "Context", "matched"},
               {"refresh", "Refresh", "Refresh", "blocked"}
             ]

    assert map_size(section_attributes) == 33
    refute Map.has_key?(section_attributes, "data-no-refresh-blocking-admin-decision-link")

    assert section_attributes
           |> Map.drop([
             "data-diagnostics-section",
             "data-no-refresh-status",
             "data-no-refresh-context",
             "data-no-refresh-refresh"
           ])
           |> Map.values()
           |> Enum.uniq() == ["-"]
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
            source_execution_retryable_count: 3,
            source_execution_actionable_count: false,
            source_execution_degraded_count: 2,
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

    vue = no_refresh_vue(html)
    summary = vue.props["summary"]
    section_attributes = summary["section"]["attributes"]
    blocker_rows = summary["blocker"]["rows"]

    assert section_attributes["data-no-refresh-blocking-boundary"] ==
             "dashboard_time_context"

    assert section_attributes["data-no-refresh-blocking-refresh-action"] ==
             "refresh_source_result"

    assert section_attributes["data-no-refresh-blocking-logical-source"] == "telemetry"

    assert section_attributes["data-no-refresh-blocking-realm"] == "replay"

    assert section_attributes["data-no-refresh-blocking-data-source"] == "questdb-replay"

    assert section_attributes["data-no-refresh-blocking-source-binding"] == "replay-binding"

    assert section_attributes["data-no-refresh-blocking-observable"] == "-"

    assert section_attributes["data-no-refresh-blocking-lifecycle-action"] ==
             "historical_data_written"

    assert section_attributes["data-no-refresh-blocking-refresh"] == "-"

    assert section_attributes["data-no-refresh-blocking-source-cache-evidence-total"] == "3"

    assert section_attributes["data-no-refresh-blocking-source-cache-evidence-targets"] ==
             "source_health_event:source-health-event-1"

    assert section_attributes["data-no-refresh-blocking-source-execution-statuses"] ==
             "cache_stale:1 source_degraded:1 source_unavailable:1"

    assert section_attributes["data-no-refresh-blocking-source-execution-actions"] ==
             "refresh_source_result:1 wait_for_source_health:2"

    assert section_attributes["data-no-refresh-blocking-source-dependency-degraded"] == "1"

    assert section_attributes["data-no-refresh-blocking-source-dependency-evidence"] ==
             "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Action") ==
             "refresh_source_result"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Identity") ==
             "telemetry:replay:questdb-replay:replay-binding"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Lifecycle") ==
             "historical_data_written"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Decision source") ==
             "runtime_health"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Placements") ==
             "placement-1,placement-2"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Source cache evidence") ==
             "total:3 resolved:1 context:1 missing:1"

    assert field_value(
             blocker_rows,
             "data-no-refresh-blocker-field",
             "Source cache evidence targets"
           ) == "source_health_event:source-health-event-1"

    assert field_value(
             blocker_rows,
             "data-no-refresh-blocker-field",
             "Source cache evidence requests"
           ) == "req-telemetry req-limits"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Source execution") ==
             "cache_stale:1 source_degraded:1 source_unavailable:1"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Source execution actions") ==
             "refresh_source_result:1 wait_for_source_health:2"

    assert field_value(blocker_rows, "data-no-refresh-blocker-field", "Source execution degraded") ==
             "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"

    assert field_value(
             blocker_rows,
             "data-no-refresh-blocker-field",
             "Source dependency degraded"
           ) ==
             "1"

    assert field_value(
             blocker_rows,
             "data-no-refresh-blocker-field",
             "Source dependency evidence"
           ) ==
             "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"

    admin_decision_link =
      section_attributes["data-no-refresh-blocking-admin-decision-link"]

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

    assert summary["admin_action"]["href"] == admin_decision_link

    assert summary["admin_action"]["attributes"] == %{
             "data-no-refresh-admin-decision-link-action" => "",
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push"
           }

    assert summary["admin_action"]["class"] == "btn btn-ghost btn-xs mt-2"
    assert summary["admin_action"]["label"] == "Runtime decision"

    assert summary["admin_action"]["icon"] == %{
             "class" => "hero-arrow-top-right-on-square h-3.5 w-3.5",
             "attributes" => %{}
           }

    assert summary["blocker"]["id"] == "dashboard-no-refresh-blocker"

    assert summary["blocker"]["class"] ==
             "mt-3 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 border-t border-warning/30 pt-2 text-xs"

    assert Enum.map(blocker_rows, &field_contract(&1, "data-no-refresh-blocker-field")) == [
             {"boundary", "Boundary", "Boundary", "dashboard_time_context"},
             {"observable", "Observable", "Observable", "-"},
             {"action", "Action", "Action", "refresh_source_result"},
             {"identity", "Identity", "Identity",
              "telemetry:replay:questdb-replay:replay-binding"},
             {"lifecycle", "Lifecycle", "Lifecycle", "historical_data_written"},
             {"decision-source", "Source", "Decision source", "runtime_health"},
             {"decision-id", "Decision ID", "Decision ID", "decision-1"},
             {"context", "Context", "Context", "scope_mismatch"},
             {"refresh", "Refresh", "Refresh", "-"},
             {"placements", "Placements", "Placements", "placement-1,placement-2"},
             {"impact", "Impact", "Impact", "source_context_filtered"},
             {"source-cache-evidence", "Evidence", "Source cache evidence",
              "total:3 resolved:1 context:1 missing:1"},
             {"source-cache-evidence-targets", "Ev targets", "Source cache evidence targets",
              "source_health_event:source-health-event-1"},
             {"source-cache-evidence-requests", "Ev requests", "Source cache evidence requests",
              "req-telemetry req-limits"},
             {"source-execution", "Src exec", "Source execution",
              "cache_stale:1 source_degraded:1 source_unavailable:1"},
             {"source-execution-actions", "Src actions", "Source execution actions",
              "refresh_source_result:1 wait_for_source_health:2"},
             {"source-execution-degraded", "Src degraded", "Source execution degraded",
              "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"},
             {"source-execution-degraded-actions", "Src d-actions",
              "Source execution degraded actions",
              "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health"},
             {"source-dependency-degraded", "Src deps", "Source dependency degraded", "1"},
             {"source-dependency-evidence", "Src dep ev", "Source dependency evidence",
              "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"}
           ]

    assert section_attributes == %{
             "data-diagnostics-section" => "No refresh summary",
             "data-no-refresh-blocking-admin-decision-link" => admin_decision_link,
             "data-no-refresh-blocking-boundary" => "dashboard_time_context",
             "data-no-refresh-blocking-context" => "scope_mismatch",
             "data-no-refresh-blocking-data-source" => "questdb-replay",
             "data-no-refresh-blocking-decision-id" => "decision-1",
             "data-no-refresh-blocking-impact" => "source_context_filtered",
             "data-no-refresh-blocking-lifecycle-action" => "historical_data_written",
             "data-no-refresh-blocking-logical-source" => "telemetry",
             "data-no-refresh-blocking-observable" => "-",
             "data-no-refresh-blocking-placements" => "placement-1,placement-2",
             "data-no-refresh-blocking-realm" => "replay",
             "data-no-refresh-blocking-refresh" => "-",
             "data-no-refresh-blocking-refresh-action" => "refresh_source_result",
             "data-no-refresh-blocking-source" => "runtime_health",
             "data-no-refresh-blocking-source-binding" => "replay-binding",
             "data-no-refresh-blocking-source-cache-evidence-context-only" => "1",
             "data-no-refresh-blocking-source-cache-evidence-missing" => "1",
             "data-no-refresh-blocking-source-cache-evidence-requests" =>
               "req-telemetry req-limits",
             "data-no-refresh-blocking-source-cache-evidence-resolved" => "1",
             "data-no-refresh-blocking-source-cache-evidence-targets" =>
               "source_health_event:source-health-event-1",
             "data-no-refresh-blocking-source-cache-evidence-total" => "3",
             "data-no-refresh-blocking-source-dependency-degraded" => "1",
             "data-no-refresh-blocking-source-dependency-evidence" =>
               "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale",
             "data-no-refresh-blocking-source-execution-actionable" => "false",
             "data-no-refresh-blocking-source-execution-actions" =>
               "refresh_source_result:1 wait_for_source_health:2",
             "data-no-refresh-blocking-source-execution-degraded" => "2",
             "data-no-refresh-blocking-source-execution-degraded-actions" =>
               "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health",
             "data-no-refresh-blocking-source-execution-degraded-identities" =>
               "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable",
             "data-no-refresh-blocking-source-execution-retryable" => "3",
             "data-no-refresh-blocking-source-execution-statuses" =>
               "cache_stale:1 source_degraded:1 source_unavailable:1",
             "data-no-refresh-context" => "matched",
             "data-no-refresh-refresh" => "blocked",
             "data-no-refresh-status" => "suppressed"
           }
  end

  test "no_refresh_summary renders nothing when hidden" do
    html =
      render_component(&RuntimeNoRefreshSummaryComponents.no_refresh_summary/1,
        summary: %{visible?: false}
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-no-refresh-summary-component")
             |> LazyHTML.attribute("id")
  end

  defp no_refresh_vue(html) do
    vue = LiveVue.Test.get_vue(html, id: "dashboard-no-refresh-summary-component")

    assert vue.id == "dashboard-no-refresh-summary-component"
    assert vue.component == "RuntimeNoRefreshSummary"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue
  end

  defp field_value(rows, attribute_name, attribute_value) do
    rows
    |> Enum.find(fn row -> row["attributes"][attribute_name] == attribute_value end)
    |> Map.fetch!("value")
  end

  defp field_contract(field, attribute_name) do
    assert field["label_class"] == "text-base-content/60"
    assert field["value_class"] == "font-mono text-base-content break-all"

    {
      field["key"],
      field["label"],
      field["attributes"][attribute_name],
      field["value"]
    }
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
