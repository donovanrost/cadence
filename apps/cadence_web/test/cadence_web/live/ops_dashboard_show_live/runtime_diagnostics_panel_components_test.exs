defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents

  test "diagnostics_panel renders runtime attributes and row sections" do
    html =
      render_component(&RuntimeDiagnosticsPanelComponents.diagnostics_panel/1,
        diagnostics: diagnostics()
      )

    document = LazyHTML.from_fragment(html)

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-invalidation-events")

    assert ["settled"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-status")

    assert ["obsolete-1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-ignored-resolve-ids")

    assert ["live_tick:tick:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-coalesced")

    assert ["live_tick:edit_mode:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-noops")

    assert ["resolve_failed:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-failures")

    assert ["telemetry:request-1:source_degraded"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-execution-degraded-identities")

    assert ["fallback:1 native:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-capability-statuses")

    assert ["telemetry:request-1:fallback:generation_time->receipt_time"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-capability-postures")

    assert "context_change" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Engine"] [data-diagnostics-field="Resolve"])
             )
             |> selected_text()

    assert "accept_result" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Runtime"] [data-diagnostics-field="Visible action"])
             )
             |> selected_text()

    assert "live_tick:tick:1" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Runtime"] [data-diagnostics-field="Refresh coalesced"])
             )
             |> selected_text()

    assert "resolve_failed:1" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Runtime"] [data-diagnostics-field="Refresh failures"])
             )
             |> selected_text()

    assert "source:2" =
             document
             |> LazyHTML.query(
               ~s([data-diagnostics-section="Invalidation"] [data-diagnostics-field="Boundaries"])
             )
             |> selected_text()
  end

  defp diagnostics(overrides \\ %{}) do
    Map.merge(
      %{
        invalidation_event_count: 3,
        invalidation_artifact_count: 4,
        invalidation_boundary_summary: "source:2",
        invalidation_context_match_count: 2,
        invalidation_context_filtered_count: 1,
        invalidation_context_filter_reasons: "scope_mismatch:1",
        invalidation_refresh_allowed_count: 1,
        invalidation_refresh_suppressed_count: 2,
        invalidation_refresh_suppress_reasons: "scope_mismatch:2",
        refresh_status: "settled",
        refresh_reason: "accepted",
        active_refresh_mode: "-",
        active_refresh_started_at: "-",
        visible_refresh_action: "accept_result",
        last_refresh_started_at: "2026-06-26T17:00:00Z",
        last_refresh_finished_at: "2026-06-26T17:00:01Z",
        last_refresh_duration_ms: "12",
        refresh_starts: "live_tick:1",
        refresh_cancellations: "-",
        refresh_coalesced: "live_tick:tick:1",
        refresh_noops: "live_tick:edit_mode:1",
        refresh_failures: "resolve_failed:1",
        refresh_ignored: "obsolete_resolve:1",
        refresh_ignored_resolve_ids: "obsolete-1",
        canceled_resolve_count: "0",
        failed_resolve_count: "0",
        source_execution_degraded_identities: "telemetry:request-1:source_degraded",
        source_execution_degraded_actions: "telemetry:request-1:wait_for_refresh:inspect_source",
        source_capability_statuses_text: "fallback:1 native:1",
        source_capability_posture_text:
          "telemetry:request-1:fallback:generation_time->receipt_time",
        source_capability_postures: [],
        engine_rows: [
          %{label: "Resolve", value: "context_change"},
          %{label: "Source requests", value: "3"}
        ],
        runtime_rows: [
          %{label: "Visible action", value: "accept_result"},
          %{label: "Refresh coalesced", value: "live_tick:tick:1"},
          %{label: "Refresh failures", value: "resolve_failed:1"},
          %{label: "Source runtime actions", value: "refresh_source_result:2"}
        ],
        invalidation_rows: [
          %{label: "Boundaries", value: "source:2"},
          %{label: "Context matches", value: "2"}
        ],
        cache_summary: %{visible?: false},
        source_execution_degraded_summary: %{visible?: false},
        source_execution_degraded_drilldowns: [],
        source_dependency_evidence: [],
        source_dependency_evidence_text: "-",
        source_dependency_degraded_count: 0,
        no_refresh_summary: %{visible?: false},
        recent_invalidations: []
      },
      overrides
    )
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end
end
