defmodule CadenceWeb.OpsDashboardShowLive.RenderContextTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, RuntimeCoordinator}
  alias CadenceWeb.OpsDashboardShowLive.RenderContext

  test "build assembles invalidation summary, diagnostics, and render model" do
    context =
      RenderContext.build(assigns(), runtime_invalidation_events: [])

    assert context.runtime_invalidation_events == []
    assert context.runtime_invalidation.event_count == 0
    assert context.runtime_diagnostics.refresh_status == "settled"
    assert context.runtime_diagnostics.refresh_reason == "accepted"
    assert context.runtime_diagnostics.invalidation_event_count == 0

    assert context.model.root_attrs["data-runtime-refresh-status"] == "settled"
    assert context.model.root_attrs["data-runtime-invalidation-events"] == 0
    assert context.model.panel_props.runtime_diagnostics == context.runtime_diagnostics
    assert context.model.panel_props.dashboard_current_path == context.model.current_path
  end

  test "model returns the prebuilt render model from context assembly" do
    model = RenderContext.model(assigns(), runtime_invalidation_events: [])
    context = RenderContext.build(assigns(), runtime_invalidation_events: [])

    assert model == context.model
    assert model.root_attrs["data-runtime-refresh-status"] == "settled"
  end

  defp assigns do
    %{
      current_scope: %{organization_id: "org-1"},
      current_mission: %{mission_id: "mission-1"},
      dashboard_document: %Document{dashboard_id: "dashboard-1"},
      dashboard_engine_result: nil,
      dashboard_runtime_coordinator: RuntimeCoordinator.new(status: :idle),
      dashboard_runtime_decisions: [%{action: :accept_result, resolve_id: 1}],
      dashboard_runtime_resolved?: true,
      dashboard_last_runtime_invalidation: nil,
      dashboard_runtime_context_since: ~U[2026-06-25 12:00:00Z],
      dashboard_render_items: [],
      dashboard_selected_data_ref: nil,
      dashboard_selection_query: nil,
      dashboard_evidence_query: nil,
      panel: nil,
      context_scope_kind: nil,
      context_scope_id: nil,
      context_query: "",
      dashboard_time_mode: "live",
      dashboard_time_from: nil,
      dashboard_time_to: nil,
      dashboard_replay_run_id: nil,
      dashboard_time_validation: "ok",
      dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
      dashboard_data_realm: "flight",
      dashboard_data_realms: ["flight"],
      dashboard_data_view: "canonical",
      dashboard_data_source_id: nil,
      dashboard_source_binding_id: nil,
      dashboard_data_bindings: [],
      dashboard_limit_mode: "observed",
      dashboard_selection_state: "none",
      dashboard_document_mode: "published",
      dashboard_lifecycle_status: nil,
      dashboard_summary: nil,
      dashboard_versions: [],
      dashboard_lifecycle_events: [],
      dashboard_publish_validation: nil,
      points: [],
      points_by_id: %{},
      operational_observables: [],
      selected_point_id: nil,
      selected_point_ids: [],
      widget_error: nil,
      widget_form: nil,
      historical_workflow_request_form: nil,
      spacecraft: [],
      chart_epoch: 0,
      edit_mode?: false
    }
  end
end
