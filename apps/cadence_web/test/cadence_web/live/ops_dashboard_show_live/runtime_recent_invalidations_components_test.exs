defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponents

  test "recent_invalidations renders invalidation attributes and field rows" do
    invalidation =
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
        source_execution_status_summary: "cache_stale:1 source_degraded:1 source_unavailable:1",
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

    html =
      render_component(&RuntimeRecentInvalidationsComponents.recent_invalidations/1,
        invalidations: [invalidation],
        dashboard_lifecycle_events: [
          lifecycle_event(
            "dashboard-lifecycle-event-published",
            :published,
            dashboard_version: 3
          )
        ],
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=diagnostics"
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-recent-invalidations-component")

    assert vue.component == "RuntimeRecentInvalidations"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]

    assert_string_data_attrs(presentation["section"]["data_attrs"])

    assert presentation["section"] == %{
             "class" => "space-y-2",
             "data_attrs" => %{"data-diagnostics-section" => "Recent invalidations"}
           }

    assert presentation["header"] == %{
             "class" => "flex items-center justify-between",
             "heading" => %{"class" => "hud-label", "text" => "Recent invalidations"},
             "count" => %{
               "class" => "font-mono text-xs text-base-content/50",
               "value" => 1
             }
           }

    assert presentation["list"] == %{
             "id" => "dashboard-recent-invalidations",
             "class" => "space-y-2"
           }

    assert presentation["empty"] == %{
             "visible" => false,
             "class" => "text-sm text-base-content/60",
             "text" => "No runtime invalidations."
           }

    assert ["dashboard-runtime-invalidation-invalidation-1"] ==
             Enum.map(presentation["events"], & &1["id"])

    [event] = presentation["events"]
    data_attrs = event["data_attrs"]

    assert_string_data_attrs(data_attrs)
    Enum.each(event["actions"], &assert_string_data_attrs(&1["data_attrs"]))
    Enum.each(event["fields"], &assert_string_data_attrs(&1["data_attrs"]))

    assert "source" == data_attrs["data-runtime-invalidation-boundary"]
    assert "dashboard-1" == data_attrs["data-runtime-invalidation-dashboard"]
    assert "mission-1" == data_attrs["data-runtime-invalidation-mission"]
    assert "telemetry" == data_attrs["data-runtime-invalidation-source"]
    assert "accepted" == data_attrs["data-runtime-invalidation-decision-status"]
    assert "1" == data_attrs["data-runtime-invalidation-source-cache-evidence-resolved"]

    assert "source_health_event:source-health-event-1" ==
             data_attrs["data-runtime-invalidation-source-cache-evidence-targets"]

    assert "cache_stale:1 source_degraded:1 source_unavailable:1" ==
             data_attrs["data-runtime-invalidation-source-execution-statuses"]

    assert "refresh_source_result:1 wait_for_source_health:2" ==
             data_attrs["data-runtime-invalidation-source-execution-actions"]

    assert "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable" ==
             data_attrs["data-runtime-invalidation-source-execution-degraded-identities"]

    assert "1" == data_attrs["data-runtime-invalidation-source-dependency-degraded"]

    assert "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale" ==
             data_attrs["data-runtime-invalidation-source-dependency-evidence"]

    assert "published" ==
             data_attrs["data-runtime-invalidation-lifecycle-correlation-state"]

    assert "Published v3 invalidated dashboard plan" ==
             data_attrs["data-runtime-invalidation-lifecycle-correlation-label"]

    assert "dashboard-lifecycle-event-published" ==
             data_attrs["data-runtime-invalidation-activity-event-id"]

    activity_link = data_attrs["data-runtime-invalidation-activity-link"]

    assert activity_link_path(activity_link) == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert activity_link_query(activity_link) == %{
             "activity_event" => "dashboard-lifecycle-event-published",
             "activity_filter" => "version_changes",
             "panel" => "versions"
           }

    activity_action = Enum.at(event["actions"], 0)

    assert activity_link == activity_action["href"]
    assert activity_action["data_attrs"]["data-phx-link"] == "redirect"
    assert activity_action["data_attrs"]["data-phx-link-state"] == "push"

    admin_decision_link = data_attrs["data-runtime-invalidation-admin-decision-link"]

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

    admin_decision_action = Enum.at(event["actions"], 1)

    assert admin_decision_link == admin_decision_action["href"]
    assert admin_decision_action["data_attrs"]["data-phx-link"] == "redirect"
    assert admin_decision_action["data_attrs"]["data-phx-link-state"] == "push"

    assert event["class"] == "border border-base-300/70 bg-base-100/40 px-2 py-2"
    assert event["badges_class"] == "flex flex-wrap items-center gap-1.5"

    assert event["badges"] == [
             %{"class" => "badge badge-xs badge-outline", "text" => "source"},
             %{"class" => "badge badge-xs", "text" => "telemetry"},
             %{"class" => "font-mono text-xs text-base-content/60", "text" => "2"}
           ]

    assert event["actions"] == [
             %{
               "href" => activity_link,
               "class" => "btn btn-ghost btn-xs mt-2",
               "text" => "Open activity",
               "data_attrs" => %{
                 "data-runtime-invalidation-activity-link-action" => "",
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push"
               },
               "icon" => %{
                 "name" => "hero-arrow-top-right-on-square",
                 "class" => "h-3.5 w-3.5"
               }
             },
             %{
               "href" => admin_decision_link,
               "class" => "btn btn-ghost btn-xs mt-2",
               "text" => "Runtime decision",
               "data_attrs" => %{
                 "data-runtime-invalidation-admin-decision-link-action" => "",
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push"
               },
               "icon" => %{
                 "name" => "hero-arrow-top-right-on-square",
                 "class" => "h-3.5 w-3.5"
               }
             }
           ]

    assert data_attrs == expected_data_attrs(activity_link, admin_decision_link)

    assert event["fields_class"] ==
             "mt-2 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs"

    assert Enum.all?(event["fields"], fn field ->
             field["label_class"] == "text-base-content/60" and
               field["value_class"] == "font-mono text-base-content break-all"
           end)

    assert Enum.map(event["fields"], &field_contract/1) == [
             {"Observable", "Observable", "HK.counter"},
             {"Realm", "Realm", "flight"},
             {"Source", "Source", "questdb-flight"},
             {"Binding", "Binding", "binding-flight"},
             {"Replay", "Replay", "replay-1"},
             {"Context", "Context", "true"},
             {"Ctx reason", "Context reason", "matched"},
             {"Allowed", "Allowed", "true"},
             {"Allow reason", "Allowed reason", "operator_context"},
             {"Decision", "Decision", "accepted"},
             {"Source", "Decision source", "runtime_health"},
             {"Decision ID", "Decision ID", "decision-1"},
             {"Decision at", "Decision observed", "2026-06-26T17:00:00Z"},
             {"Impacted", "Impacted", "2"},
             {"Placements", "Placements", "placement-1,placement-2"},
             {"Widgets", "Widgets", "cadence.value_tile"},
             {"Impact", "Impact", "source_stale"},
             {"Selection", "Selection", "-"},
             {"Sel reason", "Selection reason", "-"},
             {"Sel target", "Selection target", "-"},
             {"Sel ID", "Selection ID", "-"},
             {"Evidence", "Source cache evidence", "total:3 resolved:1 context:1 missing:1"},
             {"Ev targets", "Source cache evidence targets",
              "source_health_event:source-health-event-1"},
             {"Ev requests", "Source cache evidence requests", "req-telemetry req-limits"},
             {"Src exec", "Source execution",
              "cache_stale:1 source_degraded:1 source_unavailable:1"},
             {"Src actions", "Source execution actions",
              "refresh_source_result:1 wait_for_source_health:2"},
             {"Src degraded", "Source execution degraded",
              "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"},
             {"Src d-actions", "Source execution degraded actions",
              "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health"},
             {"Src deps", "Source dependency degraded", "1"},
             {"Src dep ev", "Source dependency evidence",
              "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"},
             {"Action", "Action", "published"},
             {"Lifecycle", "Lifecycle", "Published v3 invalidated dashboard plan"},
             {"Version", "Version", "3"},
             {"Reason", "Reason", "runtime_invalidation"},
             {"Refresh", "Refresh", "refresh_visible_widgets"},
             {"Time", "Time", "2026-06-26T17:00:01Z"}
           ]

    assert "HK.counter" == field_value(event, "Observable")
    assert "Published v3 invalidated dashboard plan" == field_value(event, "Lifecycle")
    assert "placement-1,placement-2" == field_value(event, "Placements")

    assert "total:3 resolved:1 context:1 missing:1" ==
             field_value(event, "Source cache evidence")

    assert "source_health_event:source-health-event-1" ==
             field_value(event, "Source cache evidence targets")

    assert "req-telemetry req-limits" ==
             field_value(event, "Source cache evidence requests")

    assert "cache_stale:1 source_degraded:1 source_unavailable:1" ==
             field_value(event, "Source execution")

    assert "refresh_source_result:1 wait_for_source_health:2" ==
             field_value(event, "Source execution actions")

    assert "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable" ==
             field_value(event, "Source execution degraded")

    assert "1" == field_value(event, "Source dependency degraded")

    assert "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale" ==
             field_value(event, "Source dependency evidence")

    ordered_html =
      render_component(&RuntimeRecentInvalidationsComponents.recent_invalidations/1,
        invalidations: [Map.put(invalidation, :id, "invalidation-2"), invalidation]
      )

    assert [
             "dashboard-runtime-invalidation-invalidation-2",
             "dashboard-runtime-invalidation-invalidation-1"
           ] ==
             ordered_html
             |> recent_invalidations_presentation()
             |> Map.fetch!("events")
             |> Enum.map(& &1["id"])

    string_attrs_html =
      render_component(&RuntimeRecentInvalidationsComponents.recent_invalidations/1,
        invalidations: [
          invalidation
          |> Map.put(:selection_state, false)
          |> Map.put(:selected_link_id, nil)
        ]
      )

    string_attrs_vue =
      LiveVue.Test.get_vue(string_attrs_html,
        name: "RuntimeRecentInvalidations",
        id: "dashboard-recent-invalidations-component"
      )

    assert string_attrs_vue.props == Jason.decode!(Jason.encode!(string_attrs_vue.props))

    [string_attrs_event] = string_attrs_vue.props["presentation"]["events"]
    string_attrs = string_attrs_event["data_attrs"]

    assert string_attrs["data-runtime-invalidation-selection-state"] == "false"
    refute Map.has_key?(string_attrs, "data-runtime-invalidation-selected-link")
    refute Map.has_key?(string_attrs, "data-runtime-invalidation-activity-event-id")
    refute Map.has_key?(string_attrs, "data-runtime-invalidation-activity-link")
    assert_string_data_attrs(string_attrs)
  end

  test "recent_invalidations renders empty state" do
    html =
      render_component(&RuntimeRecentInvalidationsComponents.recent_invalidations/1,
        invalidations: []
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-recent-invalidations-component")

    assert vue.component == "RuntimeRecentInvalidations"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]

    assert presentation["header"]["count"]["value"] == 0
    assert presentation["list"]["id"] == "dashboard-recent-invalidations"

    assert [] =
             presentation["events"]
             |> Enum.map(& &1["data_attrs"]["data-runtime-invalidation-boundary"])

    assert [] =
             presentation["events"]
             |> Enum.flat_map(& &1["actions"])
             |> Enum.filter(
               &Map.has_key?(
                 &1["data_attrs"],
                 "data-runtime-invalidation-admin-decision-link-action"
               )
             )
             |> Enum.map(& &1["href"])

    assert "No runtime invalidations." = presentation["empty"]["text"]

    assert presentation["empty"] == %{
             "visible" => true,
             "class" => "text-sm text-base-content/60",
             "text" => "No runtime invalidations."
           }
  end

  defp recent_invalidations_presentation(html) do
    html
    |> LiveVue.Test.get_vue(id: "dashboard-recent-invalidations-component")
    |> Map.fetch!(:props)
    |> Map.fetch!("presentation")
  end

  defp field_contract(field) do
    {
      field["label"],
      field["data_attrs"]["data-invalidation-field"],
      field["value"]
    }
  end

  defp assert_string_data_attrs(data_attrs) do
    assert Enum.all?(data_attrs, fn {key, value} -> is_binary(key) and is_binary(value) end)
  end

  defp field_value(event, data_label) do
    event["fields"]
    |> Enum.find(&(&1["data_attrs"]["data-invalidation-field"] == data_label))
    |> Map.fetch!("value")
  end

  defp expected_data_attrs(activity_link, admin_decision_link) do
    %{
      "data-runtime-invalidation-dashboard" => "dashboard-1",
      "data-runtime-invalidation-mission" => "mission-1",
      "data-runtime-invalidation-boundary" => "source",
      "data-runtime-invalidation-source" => "telemetry",
      "data-runtime-invalidation-realm" => "flight",
      "data-runtime-invalidation-data-source" => "questdb-flight",
      "data-runtime-invalidation-binding" => "binding-flight",
      "data-runtime-invalidation-replay-run-id" => "replay-1",
      "data-runtime-invalidation-observable" => "HK.counter",
      "data-runtime-invalidation-lifecycle-action" => "published",
      "data-runtime-invalidation-lifecycle-correlation-state" => "published",
      "data-runtime-invalidation-lifecycle-correlation-label" =>
        "Published v3 invalidated dashboard plan",
      "data-runtime-invalidation-lifecycle-target-version" => "3",
      "data-runtime-invalidation-lifecycle-source-version" => "-",
      "data-runtime-invalidation-activity-event-id" => "dashboard-lifecycle-event-published",
      "data-runtime-invalidation-activity-link" => activity_link,
      "data-runtime-invalidation-admin-decision-link" => admin_decision_link,
      "data-runtime-invalidation-source-version" => "source-v1",
      "data-runtime-invalidation-document-version" => "3",
      "data-runtime-invalidation-context-match" => "true",
      "data-runtime-invalidation-context-reason" => "matched",
      "data-runtime-invalidation-refresh-allowed" => "true",
      "data-runtime-invalidation-refresh-allowed-reason" => "operator_context",
      "data-runtime-invalidation-refresh-reason" => "runtime_invalidation",
      "data-runtime-invalidation-refresh-action" => "refresh_visible_widgets",
      "data-runtime-invalidation-decision-status" => "accepted",
      "data-runtime-invalidation-decision-source" => "runtime_health",
      "data-runtime-invalidation-decision-event-id" => "decision-1",
      "data-runtime-invalidation-decision-observed-at" => "2026-06-26T17:00:00Z",
      "data-runtime-invalidation-affected-placement-count" => "2",
      "data-runtime-invalidation-affected-placement-ids" => "placement-1,placement-2",
      "data-runtime-invalidation-affected-widget-types" => "cadence.value_tile",
      "data-runtime-invalidation-affected-impact-reasons" => "source_stale",
      "data-runtime-invalidation-selection-state" => "-",
      "data-runtime-invalidation-selected-link" => "-",
      "data-runtime-invalidation-selected-target" => "-",
      "data-runtime-invalidation-selected-target-id" => "-",
      "data-runtime-invalidation-selected-placement-id" => "-",
      "data-runtime-invalidation-selected-observable" => "-",
      "data-runtime-invalidation-selected-data-view" => "-",
      "data-runtime-invalidation-selection-affected" => "-",
      "data-runtime-invalidation-selection-impact-reason" => "-",
      "data-runtime-invalidation-source-cache-evidence-total" => "3",
      "data-runtime-invalidation-source-cache-evidence-resolved" => "1",
      "data-runtime-invalidation-source-cache-evidence-context-only" => "1",
      "data-runtime-invalidation-source-cache-evidence-missing" => "1",
      "data-runtime-invalidation-source-cache-evidence-targets" =>
        "source_health_event:source-health-event-1",
      "data-runtime-invalidation-source-cache-evidence-requests" => "req-telemetry req-limits",
      "data-runtime-invalidation-source-execution-retryable" => "3",
      "data-runtime-invalidation-source-execution-actionable" => "2",
      "data-runtime-invalidation-source-execution-degraded" => "2",
      "data-runtime-invalidation-source-execution-statuses" =>
        "cache_stale:1 source_degraded:1 source_unavailable:1",
      "data-runtime-invalidation-source-execution-actions" =>
        "refresh_source_result:1 wait_for_source_health:2",
      "data-runtime-invalidation-source-execution-degraded-identities" =>
        "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable",
      "data-runtime-invalidation-source-execution-degraded-actions" =>
        "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health",
      "data-runtime-invalidation-source-dependency-degraded" => "1",
      "data-runtime-invalidation-source-dependency-evidence" =>
        "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale",
      "data-runtime-invalidation-artifacts" => "2",
      "data-runtime-invalidation-occurred-at" => "2026-06-26T17:00:01Z"
    }
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
