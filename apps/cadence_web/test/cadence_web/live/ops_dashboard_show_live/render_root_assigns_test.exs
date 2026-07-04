defmodule CadenceWeb.OpsDashboardShowLive.RenderRootAssignsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, Document, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.RenderRootAssigns
  alias Phoenix.LiveView.Socket

  test "projects root render context from sockets and assigns maps" do
    socket = %Socket{assigns: assigns()}

    expected = %{
      engine_result: %{resolve_mode: :context_change},
      compare_engine_result: %{resolve_mode: :context_change},
      runtime_coordinator: %{status: :idle},
      runtime_decisions: [%{action: :accept_result}],
      runtime_resolved?: true,
      last_runtime_invalidation: %{boundary: :dashboard_version_changed},
      time_mode: "archive",
      time_axis: nil,
      time_from: "2026-06-25T11:55:00Z",
      time_to: "2026-06-25T12:00:00Z",
      replay_run_id: "replay-1",
      time_validation: "valid",
      scope_kind: "mission",
      scope_id: "mission-1",
      scope_ids: ["mission-1"],
      data_realm: "rehearsal",
      data_view: "raw",
      compare_data_view: "canonical",
      data_source_id: "questdb-rehearsal",
      source_binding_id: "rehearsal-binding",
      limit_mode: "effective",
      limit_mode_fallback: %{
        "requested_mode" => "projected",
        "applied_mode" => "observed",
        "reason" => "unsupported_limit_semantics_mode"
      },
      selection_state: "active",
      selection_target: "telemetry_sample",
      selection_source_binding: "rehearsal-binding",
      selection_data_view: "canonical",
      selection_series_role: "compare",
      selection_compare_of: "HK.counter",
      evidence_state: "query_only",
      evidence_kind: "source",
      evidence_source_request: "request-1",
      evidence_logical_source: "telemetry",
      evidence_realm: "flight",
      evidence_data_source_id: "questdb-flight",
      evidence_source_binding_id: "binding-flight",
      evidence_time_mode: "replay_run",
      evidence_time_axis: "receipt_time",
      evidence_replay_run_id: "replay-1",
      evidence_scope_kind: "spacecraft",
      evidence_scope_id: "spacecraft-1",
      evidence_scope_ids: nil,
      evidence_contact_id: "contact-1",
      evidence_source_endpoint_id: "endpoint-1",
      evidence_source_empty_reason: "contact_scope_no_data",
      evidence_requested_realm: "simulation",
      evidence_requested_data_view: "all_revisions",
      evidence_requested_data_source_id: "questdb-sim",
      evidence_requested_source_binding_id: "binding-sim",
      evidence_requested_dataset: "sim-dataset",
      evidence_requested_validity_state: "valid",
      document_mode: "draft",
      lifecycle_status: %{publish_available?: true},
      summary: %{draft_version: 2},
      versions: [%{version: 2}]
    }

    assert RenderRootAssigns.root_context(socket) == expected
    assert RenderRootAssigns.root_context(assigns()) == expected
  end

  defp assigns(overrides \\ %{}) do
    Map.merge(
      %{
        current_mission: %{mission_id: "mission-1"},
        current_scope: %{organization_id: "org-1"},
        dashboard_document: document(),
        dashboard_engine_result: %{resolve_mode: :context_change},
        dashboard_compare_engine_result: %{resolve_mode: :context_change},
        dashboard_runtime_coordinator: %{status: :idle},
        dashboard_runtime_decisions: [%{action: :accept_result}],
        dashboard_runtime_resolved?: true,
        dashboard_last_runtime_invalidation: %{boundary: :dashboard_version_changed},
        dashboard_render_items: [render_item("placement-1")],
        dashboard_selected_data_ref: selected_data_ref(),
        dashboard_selection_query: nil,
        dashboard_evidence_query: %{
          "selected_evidence_kind" => "source",
          "selected_source_request" => "request-1",
          "selected_logical_source" => "telemetry",
          "selected_realm" => "flight",
          "selected_data_source" => "questdb-flight",
          "selected_source_binding" => "binding-flight",
          "selected_time_mode" => "replay_run",
          "selected_time_axis" => "receipt_time",
          "selected_replay_run_id" => "replay-1",
          "selected_scope_kind" => "spacecraft",
          "selected_scope_id" => "spacecraft-1",
          "selected_contact_id" => "contact-1",
          "selected_source_endpoint_id" => "endpoint-1",
          "selected_source_empty_reason" => "contact_scope_no_data",
          "selected_requested_realm" => "simulation",
          "selected_requested_data_view" => "all_revisions",
          "selected_requested_data_source" => "questdb-sim",
          "selected_requested_source_binding" => "binding-sim",
          "selected_requested_dataset" => "sim-dataset",
          "selected_requested_validity_state" => "valid"
        },
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        context_scope_ids: ["mission-1"],
        context_spacecraft_id: "SC-1",
        context_query: "temp",
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T11:55:00Z",
        dashboard_time_to: "2026-06-25T12:00:00Z",
        dashboard_replay_run_id: "replay-1",
        dashboard_time_validation: "valid",
        dashboard_time_context: %{"mode" => "archive"},
        dashboard_runtime_context_since: ~U[2026-06-25 12:00:00Z],
        dashboard_data_realm: "rehearsal",
        dashboard_data_realms: ["flight", "rehearsal"],
        dashboard_data_view: "raw",
        dashboard_compare_data_view: "canonical",
        dashboard_data_source_id: "questdb-rehearsal",
        dashboard_source_binding_id: "rehearsal-binding",
        dashboard_data_bindings: [data_binding()],
        dashboard_limit_mode: "effective",
        dashboard_limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        dashboard_document_mode: "draft",
        dashboard_lifecycle_status: %{publish_available?: true},
        dashboard_summary: %{draft_version: 2},
        dashboard_versions: [%{version: 2}],
        dashboard_lifecycle_events: [%{event_type: :published}],
        dashboard_publish_validation: %{valid?: true},
        edit_mode?: true,
        spacecraft: [%{spacecraft_id: "SC-1"}],
        operational_observables: [%{observable_id: "obs.temp"}],
        points: [%{point_id: "HK.temp"}],
        points_by_id: %{"HK.temp" => %{point_id: "HK.temp"}},
        widget_data: %{"placement-1" => %{kind: :legacy_point}},
        backfills: %{"placement-1" => %{state: :requested}},
        dashboard_engine_frames_by_placement: %{"placement-1" => %{frame: :engine}},
        selected_point_id: "HK.temp",
        selected_point_ids: ["HK.temp", "obs.temp"],
        widget_error: "invalid widget",
        panel: :add_widget,
        chart_epoch: 4
      },
      overrides
    )
  end

  defp document do
    %Document{dashboard_id: "dashboard-1"}
  end

  defp selected_data_ref do
    %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "source_binding_id" => "rehearsal-binding",
      "data_view" => "canonical",
      "series_role" => "compare",
      "compare_of" => "HK.counter"
    }
  end

  defp render_item(placement_id) do
    %{
      placement_id: placement_id,
      widget: %RenderWidget{
        widget_id: "widget-1",
        type: :value_tile,
        title: "Temperature",
        binding: %{source: :telemetry, mode: :context}
      }
    }
  end

  defp data_binding do
    %DataBinding{
      binding_id: "rehearsal-binding",
      data_source_id: "questdb-rehearsal",
      dataset: "rehearsal",
      realm: :rehearsal,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end
end
