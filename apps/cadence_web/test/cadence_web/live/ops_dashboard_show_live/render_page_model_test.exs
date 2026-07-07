defmodule CadenceWeb.OpsDashboardShowLive.RenderPageModelTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DataBinding,
    Document,
    Field,
    Frame,
    PlacementFrames,
    RenderWidget
  }

  alias CadenceWeb.OpsDashboardShowLive.{
    RenderGridModel,
    RenderPageModel,
    RenderPanelModel,
    RenderRootAssigns,
    RenderRootAttrs,
    RenderSelectionModel,
    RenderSourceModel,
    RenderToolbarModel
  }

  test "build assembles current path, context visibility, selection, and evidence" do
    assigns =
      assigns(%{
        dashboard_render_items: [
          render_item("context-placement"),
          render_item("fixed-placement", %{widget: render_widget(%{binding: %{mode: :fixed}})})
        ],
        dashboard_selected_data_ref: %{
          "target" => "telemetry_sample",
          "target_id" => "sample-1",
          "source_binding_id" => "flight-binding"
        },
        dashboard_evidence_query: %{
          "selected_evidence_kind" => "source",
          "selected_source_request" => "request-1",
          "selected_logical_source" => "telemetry",
          "selected_realm" => "flight",
          "selected_data_source" => "questdb-flight",
          "selected_source_binding" => "flight-binding",
          "selected_time_mode" => "replay_run",
          "selected_time_axis" => "receipt_time",
          "selected_replay_run_id" => "replay-1",
          "selected_requested_realm" => "simulation",
          "selected_requested_data_view" => "all_revisions",
          "selected_requested_data_source" => "questdb-sim",
          "selected_requested_source_binding" => "binding-sim",
          "selected_requested_dataset" => "sim-dataset",
          "selected_requested_validity_state" => "valid"
        },
        dashboard_comparison_review_queue: %{
          count: 1,
          count_text: "1",
          requests: [%{dashboard_lifecycle_event_id: "request-1"}],
          request_ids: ["request-1"],
          request_ids_attr: "request-1",
          placement_ids: ["placement-1"],
          placements_attr: "placement-1"
        }
      })

    model =
      assigns
      |> RenderPageModel.build()

    assert model.current_path ==
             "/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence&selected_data_source=questdb-flight&selected_evidence_kind=source&selected_id=sample-1&selected_logical_source=telemetry&selected_realm=flight&selected_replay_run_id=replay-1&selected_requested_data_source=questdb-sim&selected_requested_data_view=all_revisions&selected_requested_dataset=sim-dataset&selected_requested_realm=simulation&selected_requested_source_binding=binding-sim&selected_requested_validity_state=valid&selected_source_binding=flight-binding&selected_source_request=request-1&selected_target=telemetry_sample&selected_time_axis=receipt_time&selected_time_mode=replay_run&source_binding_id=flight-binding"

    assert model.show_context? == true
    assert model.source_selection_props == RenderSourceModel.source_selection_props(assigns)
    assert model.open_review_summary == assigns.dashboard_comparison_review_queue
    assert model.selection == RenderSelectionModel.selection(assigns)
    assert model.evidence == RenderSelectionModel.evidence(assigns)
    assert model.root_attrs["data-dashboard-evidence-logical-source"] == "telemetry"
    assert model.root_attrs["data-dashboard-evidence-realm"] == "flight"
    assert model.root_attrs["data-dashboard-evidence-data-source-id"] == "questdb-flight"
    assert model.root_attrs["data-dashboard-evidence-source-binding-id"] == "flight-binding"
    assert model.root_attrs["data-dashboard-evidence-time-mode"] == "replay_run"
    assert model.root_attrs["data-dashboard-evidence-time-axis"] == "receipt_time"
    assert model.root_attrs["data-dashboard-evidence-replay-run-id"] == "replay-1"
    assert model.root_attrs["data-dashboard-evidence-requested-realm"] == "simulation"
    assert model.root_attrs["data-dashboard-evidence-requested-data-view"] == "all_revisions"
    assert model.root_attrs["data-dashboard-evidence-requested-data-source-id"] == "questdb-sim"

    assert model.root_attrs["data-dashboard-evidence-requested-source-binding-id"] ==
             "binding-sim"

    assert model.root_attrs["data-dashboard-evidence-requested-dataset"] == "sim-dataset"
    assert model.root_attrs["data-dashboard-evidence-requested-validity-state"] == "valid"
  end

  test "build defaults absent review queue to the canonical empty queue" do
    open_lifecycle_event = %{
      dashboard_lifecycle_event_id: "request-from-lifecycle-events",
      event_type: :comparison_review_requested,
      occurred_at: ~U[2026-06-24 12:00:00Z],
      payload: %{"open_findings" => %{"findings" => [%{"placement_id" => "placement-1"}]}}
    }

    model =
      assigns(%{
        dashboard_lifecycle_events: [open_lifecycle_event],
        dashboard_comparison_review_queue: nil
      })
      |> RenderPageModel.build()

    assert model.open_review_summary == empty_review_queue()
    assert model.toolbar_props.dashboard_comparison_review_queue == empty_review_queue()
    assert model.panel_props.dashboard_comparison_review_queue == empty_review_queue()
  end

  test "build reports query-only and missing selection states" do
    query_only =
      assigns(%{
        dashboard_selection_query: %{
          "selected_target" => "telemetry_sample",
          "selected_id" => "sample-1"
        }
      })
      |> RenderPageModel.build()

    assert query_only.selection.state == "query_only"
    assert query_only.selection.target == "telemetry_sample"

    missing =
      assigns(%{panel: {:data_link, %{status: :missing}}})
      |> RenderPageModel.build()

    assert missing.selection.state == "missing_target"
  end

  test "build prepares page shell attrs from static layout and root diagnostics" do
    model =
      assigns(%{dashboard_time_mode: "archive"})
      |> RenderPageModel.build(%{refresh_status: "settled"}, %{event_count: 2})

    assert model.page_attrs.id == "ops-dashboard-show-page"
    assert model.page_attrs.class == "flex flex-col flex-1 min-h-0"
    assert model.page_attrs["data-dashboard-time-mode"] == "archive"
    assert model.page_attrs["data-runtime-refresh-status"] == "settled"
    assert model.page_attrs["data-runtime-invalidation-events"] == 2
    assert model.root_attrs["data-dashboard-time-mode"] == "archive"
    assert model.root_attrs["data-dashboard-evidence-logical-source"] == nil
    assert model.root_attrs["data-dashboard-evidence-realm"] == nil
    assert model.root_attrs["data-dashboard-evidence-data-source-id"] == nil
    assert model.root_attrs["data-dashboard-evidence-source-binding-id"] == nil
    assert model.root_attrs["data-dashboard-evidence-time-mode"] == nil
    assert model.root_attrs["data-dashboard-evidence-time-axis"] == nil
    assert model.root_attrs["data-dashboard-evidence-replay-run-id"] == nil
    assert model.root_attrs["data-dashboard-evidence-requested-realm"] == nil
    assert model.root_attrs["data-dashboard-evidence-requested-data-view"] == nil
    assert model.root_attrs["data-dashboard-evidence-requested-data-source-id"] == nil
    assert model.root_attrs["data-dashboard-evidence-requested-source-binding-id"] == nil
    assert model.root_attrs["data-dashboard-evidence-requested-dataset"] == nil
    assert model.root_attrs["data-dashboard-evidence-requested-validity-state"] == nil
    assert model.content_attrs == %{class: "flex-1 min-w-0 min-h-0 overflow-y-auto"}
  end

  test "build assembles grid and panel section props" do
    assigns = assigns(%{panel: :add_widget})
    runtime_diagnostics = %{refresh_status: "settled"}

    model =
      assigns
      |> RenderPageModel.build(runtime_diagnostics, %{})

    assert model.empty_state == RenderGridModel.empty_state(assigns)
    assert model.panel_open? == RenderPanelModel.open?(assigns)

    assert model.panel_props ==
             RenderPanelModel.props(assigns, runtime_diagnostics, model.current_path)
  end

  test "build prepares widget items" do
    assigns =
      assigns(%{
        edit_mode?: true,
        dashboard_render_items: [
          render_item("placement-1", %{layout: %{x: nil, y: 2, w: 5, h: 4}})
        ]
      })

    model =
      assigns
      |> RenderPageModel.build()

    assert model.grid_props == RenderGridModel.grid_props(assigns)
    assert [widget_item] = model.widget_items
    assert widget_item.item.placement_id == "placement-1"
  end

  test "build exposes dashboard-level comparison rollup attrs" do
    assigns =
      assigns(%{
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_render_items: [
          render_item("placement-1"),
          render_item("placement-2", %{widget: render_widget(%{widget_id: "widget-2"})})
        ],
        dashboard_engine_frames_by_placement: %{
          "placement-1" => scalar_frames(42),
          "placement-2" => scalar_frames(40)
        },
        dashboard_compare_engine_frames_by_placement: %{
          "placement-1" => scalar_frames(40),
          "placement-2" => %PlacementFrames{}
        },
        dashboard_comparison_decision_events: [
          comparison_decision_event("placement-1",
            decision_event_id: "decision-event-1",
            decision: :mark_conflict,
            decision_reason: "operator_confirmed_comparison"
          )
        ]
      })

    model = RenderPageModel.build(assigns)

    assert model.root_attrs["data-dashboard-comparison-widgets"] == 2
    assert model.root_attrs["data-dashboard-comparison-deltas"] == 1
    assert model.root_attrs["data-dashboard-comparison-missing"] == 1
    assert model.root_attrs["data-dashboard-comparison-states"] == "increased,missing"
    assert model.root_attrs["data-dashboard-comparison-handled"] == 1
    assert model.root_attrs["data-dashboard-comparison-open"] == 1
    assert model.root_attrs["data-dashboard-comparison-unhandled"] == 1
    assert model.root_attrs["data-dashboard-comparison-delta-placements"] == "placement-1"
    assert model.root_attrs["data-dashboard-comparison-missing-placements"] == "placement-2"
    assert model.root_attrs["data-dashboard-comparison-open-placements"] == "placement-2"
    assert model.root_attrs["data-dashboard-comparison-handled-placements"] == "placement-1"
    assert model.page_attrs["data-dashboard-comparison-deltas"] == 1
    assert model.comparison_rollup.visible? == true
    assert model.comparison_rollup.widget_count == 2
    assert model.comparison_rollup.delta_count == 1
    assert model.comparison_rollup.missing_count == 1
    assert model.comparison_preset["schema"] == "dashboard_comparison_investigation_preset.v1"
    assert model.comparison_preset["dashboard_id"] == "dashboard-1"
    assert model.comparison_preset["mission_id"] == "mission-1"

    assert model.comparison_preset["runtime_query"] == %{
             "compare_data_view" => "canonical",
             "data_view" => "all_revisions",
             "source_binding_id" => "primary"
           }

    assert model.comparison_preset["comparison"]["primary_data_view"] == "all_revisions"
    assert model.comparison_preset["comparison"]["compare_data_view"] == "canonical"
    assert model.comparison_preset["comparison"]["delta_count"] == 1
    assert model.comparison_preset["comparison"]["missing_count"] == 1
    assert model.comparison_preset["comparison"]["handled_count"] == 1
    assert model.comparison_preset["comparison"]["open_count"] == 1
    assert model.comparison_preset["comparison"]["unhandled_count"] == 1

    assert [
             %{
               "key" => "deltas",
               "placement_ids" => ["placement-1"],
               "items" => [
                 %{
                   "placement_id" => "placement-1",
                   "state" => "increased",
                   "decision_status" => "applied",
                   "decision_event_id" => "decision-event-1",
                   "decision" => "mark_conflict",
                   "decision_reason" => "operator_confirmed_comparison"
                 }
               ]
             },
             %{
               "key" => "missing",
               "placement_ids" => ["placement-2"],
               "items" => [%{"placement_id" => "placement-2", "state" => "missing"}]
             }
           ] = model.comparison_preset["groups"]

    assert [
             %{
               "key" => "open",
               "placement_ids" => ["placement-2"],
               "items" => [
                 %{
                   "placement_id" => "placement-2",
                   "state" => "missing",
                   "decision_status" => "unhandled"
                 }
               ]
             },
             %{
               "key" => "handled",
               "placement_ids" => ["placement-1"],
               "items" => [
                 %{
                   "placement_id" => "placement-1",
                   "decision_status" => "applied",
                   "decision_event_id" => "decision-event-1"
                 }
               ]
             }
           ] = model.comparison_preset["workflow_groups"]

    assert model.comparison_preset["current_path"] =~
             "/missions/mission-1/ops/dashboards/dashboard-1?"

    assert [
             %{
               key: "deltas",
               placement_ids: "placement-1",
               handled_count: 1,
               unhandled_count: 0
             },
             %{key: "missing", placement_ids: "placement-2"}
           ] = model.comparison_rollup.groups

    assert [
             %{key: "open", placement_ids: "placement-2", count: 1},
             %{key: "handled", placement_ids: "placement-1", count: 1}
           ] = model.comparison_rollup.workflow_groups
  end

  test "build exposes dashboard-level health rollup attrs" do
    model =
      assigns(%{
        current_scope: %{organization_id: "org-1"},
        context_scope_kind: "contact",
        context_scope_id: "contact-1",
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-26T12:00:00Z",
        dashboard_time_to: "2026-06-26T12:05:00Z",
        dashboard_data_view: "all_revisions",
        dashboard_data_source_id: "questdb-flight",
        dashboard_source_binding_id: "binding-flight",
        dashboard_render_items: [
          render_item("ready-placement", %{widget: render_widget(%{title: "Ready"})}),
          render_item("stale-placement", %{widget: render_widget(%{title: "Stale"})}),
          render_item("blocked-placement", %{widget: render_widget(%{title: "Blocked"})})
        ],
        widget_data: %{
          "ready-placement" => %{kind: :point, lifecycle_state: :ready},
          "stale-placement" => %{
            kind: :point,
            lifecycle_state: :ready,
            source_status: %{state: :stale}
          },
          "blocked-placement" => %{
            kind: :point,
            lifecycle_state: :ready,
            source_status: %{state: :unavailable}
          }
        }
      })
      |> RenderPageModel.build()

    assert model.dashboard_health.state == :blocked
    assert model.dashboard_health.widget_count == 3
    assert model.dashboard_health.ready_count == 1
    assert model.dashboard_health.stale_count == 1
    assert model.dashboard_health.blocked_count == 1
    assert model.dashboard_health.affected_placements == "stale-placement,blocked-placement"
    assert model.dashboard_health.snapshot_schema == "dashboard_health_snapshot.v1"
    assert model.dashboard_health.snapshot_id == model.dashboard_health.snapshot["snapshot_id"]

    assert String.starts_with?(
             model.dashboard_health.snapshot_id,
             "dashboard_health_snapshot_"
           )

    assert model.dashboard_health.snapshot["schema"] == "dashboard_health_snapshot.v1"
    assert model.dashboard_health.snapshot["organization_id"] == "org-1"
    assert model.dashboard_health.snapshot["mission_id"] == "mission-1"
    assert model.dashboard_health.snapshot["dashboard_id"] == "dashboard-1"

    assert model.dashboard_health.snapshot["runtime_context"] == %{
             "realm" => "flight",
             "data_view" => "all_revisions",
             "time_mode" => "archive",
             "time_from" => "2026-06-26T12:00:00Z",
             "time_to" => "2026-06-26T12:05:00Z",
             "scope_kind" => "contact",
             "scope_id" => "contact-1",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed"
           }

    assert model.dashboard_health.snapshot["placement_ids"]["affected"] == [
             "stale-placement",
             "blocked-placement"
           ]

    assert [
             %{"placement_id" => "ready-placement", "state" => "ready"},
             %{"placement_id" => "stale-placement", "state" => "stale"},
             %{"placement_id" => "blocked-placement", "state" => "blocked"}
           ] = model.dashboard_health.snapshot["items"]

    assert model.root_attrs["data-dashboard-health-snapshot-schema"] ==
             "dashboard_health_snapshot.v1"

    assert model.root_attrs["data-dashboard-health-snapshot-id"] ==
             model.dashboard_health.snapshot_id

    assert model.root_attrs["data-dashboard-health-state"] == "blocked"
    assert model.root_attrs["data-dashboard-health-widgets"] == 3
    assert model.root_attrs["data-dashboard-health-stale-placements"] == "stale-placement"
    assert model.root_attrs["data-dashboard-health-blocked-placements"] == "blocked-placement"
  end

  test "build assembles toolbar, dashboard warning, and source health props" do
    document = document()
    data_bindings = [data_binding()]
    selected_ref = %{"target" => "telemetry_sample"}

    assigns =
      assigns(%{
        dashboard_document: document,
        dashboard_lifecycle_status: %{publish_available?: true},
        edit_mode?: true,
        dashboard_render_items: [render_item("placement-1")],
        spacecraft: [%{spacecraft_id: "SC-1"}],
        context_spacecraft_id: "SC-1",
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T11:55:00Z",
        dashboard_time_to: "2026-06-25T12:00:00Z",
        dashboard_replay_run_id: "replay-1",
        dashboard_time_validation: "ok",
        dashboard_data_realm: "rehearsal",
        dashboard_data_realms: ["flight", "rehearsal"],
        dashboard_data_view: "raw",
        dashboard_data_source_id: "questdb-rehearsal",
        dashboard_source_binding_id: "rehearsal-binding",
        dashboard_data_bindings: data_bindings,
        dashboard_limit_mode: "effective",
        dashboard_selected_data_ref: selected_ref,
        context_query: "sc",
        dashboard_engine_result: degraded_engine_result()
      })

    model =
      assigns
      |> RenderPageModel.build()

    assert model.toolbar_props == RenderToolbarModel.props(assigns)
    assert model.dashboard_warning_props == RenderSourceModel.dashboard_warning_props(assigns)
    assert model.source_health_props == RenderSourceModel.source_health_props(assigns)
  end

  test "build carries assigned source summaries through page props" do
    model =
      assigns(%{
        dashboard_warning_summaries: [%{code: :assigned_warning}],
        dashboard_degraded?: true,
        dashboard_source_health_summaries: [%{source_health_event_id: "health-1"}],
        dashboard_source_selection_summaries: [%{request_id: "req-1"}]
      })
      |> RenderPageModel.build()

    assert model.dashboard_warning_props == %{
             warnings: [%{code: :assigned_warning}],
             degraded?: true
           }

    assert model.source_health_props == %{health: [%{source_health_event_id: "health-1"}]}

    assert model.source_selection_props == %{
             mission_id: "mission-1",
             selections: [%{request_id: "req-1"}]
           }
  end

  test "root attr groups isolate engine, runtime, invalidation, and dashboard state" do
    context =
      assigns(%{
        dashboard_engine_result: engine_result(),
        dashboard_compare_engine_result: compare_engine_result(),
        dashboard_runtime_coordinator: %{status: :idle},
        dashboard_runtime_decisions: [
          %{action: :start_resolve, resolve_mode: :live_tick, reason: :tick}
        ],
        dashboard_runtime_resolved?: true,
        dashboard_last_runtime_invalidation: %{
          boundary: :dashboard_version_changed,
          refresh_reason: :runtime_invalidation,
          refresh_action: :remount_charts
        },
        dashboard_time_mode: "archive",
        dashboard_document_mode: "draft"
      })
      |> RenderRootAssigns.root_context()

    engine_attrs = RenderRootAttrs.engine_root_attrs(context)
    assert engine_attrs["data-engine-resolve-mode"] == "context_change"
    assert engine_attrs["data-engine-source-requests"] == 3
    assert engine_attrs["data-engine-source-dependencies"] == "limits->telemetry:latest_sample"
    assert engine_attrs["data-engine-source-dependency-count"] == 1
    assert engine_attrs["data-engine-source-dependency-evidence"] == nil
    assert engine_attrs["data-engine-source-dependency-degraded-count"] == 0
    assert engine_attrs["data-compare-engine-resolve-mode"] == "context_change"
    assert engine_attrs["data-compare-engine-data-view"] == "all_revisions"
    refute Map.has_key?(engine_attrs, "data-runtime-status")
    refute Map.has_key?(engine_attrs, "data-dashboard-time-mode")

    runtime_attrs = RenderRootAttrs.runtime_root_attrs(context, %{refresh_status: "settled"})
    assert runtime_attrs["data-runtime-status"] == "idle"
    assert runtime_attrs["data-runtime-refresh-status"] == "settled"
    refute Map.has_key?(runtime_attrs, "data-engine-resolve-mode")
    refute Map.has_key?(runtime_attrs, "data-dashboard-document-mode")

    invalidation_attrs =
      RenderRootAttrs.runtime_invalidation_root_attrs(
        context,
        %{invalidation_context_match_count: 2},
        %{event_count: 4, boundaries: %{dashboard_version_changed: 2}}
      )

    assert invalidation_attrs["data-runtime-invalidation-events"] == 4
    assert invalidation_attrs["data-runtime-last-invalidation-refresh-action"] == "remount_charts"
    refute Map.has_key?(invalidation_attrs, "data-runtime-status")
    refute Map.has_key?(invalidation_attrs, "data-dashboard-document-mode")

    dashboard_attrs = RenderRootAttrs.dashboard_root_attrs(context)
    assert dashboard_attrs["data-dashboard-time-mode"] == "archive"
    assert dashboard_attrs["data-dashboard-document-mode"] == "draft"
    refute Map.has_key?(dashboard_attrs, "data-engine-resolve-mode")
    refute Map.has_key?(dashboard_attrs, "data-runtime-status")
  end

  test "root_attrs exposes engine, runtime, invalidation, and dashboard diagnostics" do
    attrs =
      assigns(%{
        dashboard_engine_result: engine_result(),
        dashboard_compare_engine_result: compare_engine_result(),
        dashboard_runtime_coordinator: %{status: :idle},
        dashboard_runtime_decisions: [
          %{action: :start_resolve, resolve_mode: :live_tick, reason: :tick}
        ],
        dashboard_runtime_resolved?: true,
        dashboard_last_runtime_invalidation: %{
          boundary: :dashboard_version_changed,
          refresh_reason: :runtime_invalidation,
          refresh_action: :remount_charts
        },
        dashboard_time_mode: "archive",
        dashboard_time_from: "2026-06-25T11:55:00Z",
        dashboard_time_to: "2026-06-25T12:00:00Z",
        dashboard_time_validation: "ok",
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        context_scope_ids: ["mission-1"],
        dashboard_limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        dashboard_document_mode: "draft",
        dashboard_selected_data_ref: %{
          "target" => "telemetry_sample",
          "source_binding_id" => "flight-binding",
          "data_view" => "canonical",
          "series_role" => "compare",
          "compare_of" => "HK.counter"
        }
      })
      |> RenderRootAttrs.root_attrs(
        %{
          refresh_status: "settled",
          refresh_reason: "accepted",
          visible_refresh_action: "accept_result",
          refresh_starts: "live_tick:tick:1",
          refresh_cancellations: "context_change:runtime_invalidation:1",
          refresh_coalesced: "live_tick:tick:1",
          refresh_noops: "live_tick:edit_mode:1",
          refresh_failures: "resolve_failed:1",
          refresh_ignored: "obsolete_resolve:1",
          refresh_ignored_resolve_ids: "obsolete-1",
          canceled_resolve_count: 1,
          failed_resolve_count: 1,
          invalidation_context_match_count: 2,
          invalidation_context_filtered_count: 1,
          invalidation_context_filter_reasons: "scope_mismatch:1",
          invalidation_refresh_allowed_count: 1,
          invalidation_refresh_suppressed_count: 1,
          invalidation_refresh_suppress_reasons: "edit_mode:1",
          source_execution_runtime_actions: "refresh_source_result:2",
          source_execution_retryable_count: 1,
          source_execution_actionable_count: 2,
          source_execution_degraded_count: 3,
          source_execution_degraded_identities: "telemetry:req-1:timeout",
          source_execution_degraded_actions: "telemetry:req-1:retry:inspect"
        },
        %{event_count: 4, artifact_count: 5, boundaries: %{dashboard_version_changed: 2}}
      )

    assert attrs["data-engine-resolve-mode"] == "context_change"
    assert attrs["data-engine-source-requests"] == 3
    assert attrs["data-engine-plan-cache"] == "hit"
    assert attrs["data-engine-data-realm"] == "flight"
    assert attrs["data-engine-source-binding-id"] == "flight-binding"
    assert attrs["data-engine-source-dependencies"] == "limits->telemetry:latest_sample"
    assert attrs["data-engine-source-dependency-count"] == 1
    assert attrs["data-engine-source-dependency-evidence"] == nil
    assert attrs["data-engine-source-dependency-degraded-count"] == 0
    assert attrs["data-compare-engine-data-view"] == "all_revisions"
    assert attrs["data-runtime-status"] == "idle"
    assert attrs["data-runtime-refresh-status"] == "settled"
    assert attrs["data-runtime-refresh-starts"] == "live_tick:tick:1"
    assert attrs["data-runtime-refresh-cancellations"] == "context_change:runtime_invalidation:1"
    assert attrs["data-runtime-refresh-coalesced"] == "live_tick:tick:1"
    assert attrs["data-runtime-refresh-noops"] == "live_tick:edit_mode:1"
    assert attrs["data-runtime-refresh-failures"] == "resolve_failed:1"
    assert attrs["data-runtime-refresh-ignored"] == "obsolete_resolve:1"
    assert attrs["data-runtime-refresh-ignored-resolve-ids"] == "obsolete-1"
    assert attrs["data-runtime-canceled-resolves"] == 1
    assert attrs["data-runtime-failed-resolves"] == 1
    assert attrs["data-runtime-resolved"] == "true"
    assert attrs["data-runtime-invalidation-events"] == 4
    assert attrs["data-runtime-invalidation-boundaries"] == "dashboard_version_changed:2"
    assert attrs["data-runtime-last-invalidation-boundary"] == "dashboard_version_changed"
    assert attrs["data-runtime-last-invalidation-refresh-action"] == "remount_charts"
    assert attrs["data-runtime-source-execution-actions"] == "refresh_source_result:2"
    assert attrs["data-dashboard-time-mode"] == "archive"
    assert attrs["data-dashboard-scope-kind"] == "mission"
    assert attrs["data-dashboard-scope-id"] == "mission-1"
    assert attrs["data-dashboard-scope-ids"] == "mission-1"
    assert attrs["data-dashboard-limit-mode-requested"] == "projected"

    assert attrs["data-dashboard-limit-mode-fallback-reason"] ==
             "unsupported_limit_semantics_mode"

    assert attrs["data-dashboard-selection-state"] == "active"
    assert attrs["data-dashboard-selection-target"] == "telemetry_sample"
    assert attrs["data-dashboard-selection-data-view"] == "canonical"
    assert attrs["data-dashboard-selection-series-role"] == "compare"
    assert attrs["data-dashboard-selection-compare-of"] == "HK.counter"
    assert attrs["data-dashboard-document-mode"] == "draft"
    assert attrs["data-dashboard-publication-state"] == "unknown"
    assert attrs["data-dashboard-published-current"] == "false"
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_data_realms: ["flight"],
        dashboard_data_bindings: [data_binding()],
        dashboard_render_items: [],
        dashboard_selected_data_ref: nil,
        dashboard_selection_query: nil,
        dashboard_evidence_query: nil,
        panel: nil,
        context_scope_kind: nil,
        context_scope_id: nil,
        dashboard_time_mode: "live",
        dashboard_time_from: nil,
        dashboard_time_to: nil,
        dashboard_replay_run_id: nil,
        dashboard_data_realm: "flight",
        dashboard_data_view: "canonical",
        dashboard_data_source_id: nil,
        dashboard_source_binding_id: nil,
        dashboard_limit_mode: "observed",
        dashboard_limit_mode_fallback: nil,
        dashboard_selection_state: "none",
        dashboard_time_validation: "ok",
        dashboard_runtime_resolved?: false,
        dashboard_runtime_coordinator: nil,
        dashboard_runtime_decisions: [],
        dashboard_last_runtime_invalidation: nil,
        dashboard_document_mode: "published",
        dashboard_lifecycle_status: nil,
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: empty_review_queue(),
        dashboard_publish_validation: nil,
        points: [],
        operational_observables: [],
        selected_point_id: nil,
        selected_point_ids: [],
        widget_error: nil,
        widget_form: nil,
        historical_workflow_request_form: nil,
        spacecraft: [],
        context_query: ""
      },
      overrides
    )
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "flight-binding"}
          },
          "view" => "canonical"
        }
      }
    }
  end

  defp render_item(placement_id, attrs \\ %{}) do
    Map.merge(
      %{
        placement_id: placement_id,
        layout: %{x: 0, y: 0, w: 4, h: 3},
        widget: render_widget()
      },
      attrs
    )
  end

  defp render_widget(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          widget_id: "widget-1",
          type: :value_tile,
          title: "Temperature",
          binding: %{
            source: :telemetry,
            mode: :context,
            spacecraft_id: nil,
            point_id: "HK.temp",
            point_ids: ["HK.temp"]
          },
          options: %{precision: 2, window_seconds: 300}
        },
        attrs
      )

    struct!(RenderWidget, attrs)
  end

  defp data_binding(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        binding_id: "flight-binding",
        data_source_id: "questdb-flight",
        dataset: "flight",
        realm: :flight,
        logical_source: :telemetry,
        priority: 0,
        status: :active
      })

    struct!(DataBinding, attrs)
  end

  defp scalar_frames(value) do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          scope: %{primary: %{ids: ["spacecraft-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.temp", kind: :number, values: [value]}
          ],
          meta: %{observable_id: "HK.temp", warning_codes: []}
        }
      ]
    }
  end

  defp empty_review_queue do
    ComparisonReviewQueue.open_summary([])
  end

  defp comparison_decision_event(placement_id, overrides) do
    attrs =
      Map.merge(
        %{
          decision_event_id: "decision-event-#{placement_id}",
          decision: :mark_conflict,
          decision_reason: "dashboard_comparison_finding",
          occurred_at: ~U[2026-06-17 12:05:00Z],
          evidence_ref: %{
            "source_target" => "comparison_finding",
            "source_target_id" => placement_id,
            "comparison_finding" => %{
              "placement_id" => placement_id,
              "state" => "increased"
            },
            "correction_workflow" => %{"authority" => "comparison"}
          }
        },
        Map.new(overrides)
      )

    struct!(Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent, attrs)
  end

  defp engine_result do
    %{
      resolve_mode: :context_change,
      plan_metadata: %{
        source_request_count: 3,
        executed_source_request_count: 2,
        skipped_source_request_count: 1,
        snapshot?: true,
        live_append_eligible?: false,
        time: %{mode: "archive", replay_run_id: nil},
        cache: %{
          plan_cache: %{status: :hit},
          source_result_cache_by_request_id: %{"req-1" => %{status: :hit}},
          frame_cache_by_placement: %{"placement-1" => [%{status: :miss}]}
        }
      },
      planned_source_requests: [
        %{
          request_id: "req-1",
          logical_source: :telemetry,
          data_context: %{
            realm: "flight",
            source_contexts: %{
              telemetry: %{
                data_source_id: "questdb-flight",
                source_binding_id: "flight-binding",
                view: "canonical"
              }
            }
          },
          limit_context: %{semantics_mode: "observed"}
        },
        %{
          request_id: "req-limits",
          logical_source: :limits,
          source_dependencies: [
            %{
              logical_source: :telemetry,
              reason: :limit_latest_sample_input,
              products: [:latest_sample],
              sampling: %{mode: :latest}
            }
          ],
          data_context: %{realm: "flight"},
          limit_context: %{semantics_mode: "compare"}
        }
      ]
    }
  end

  defp degraded_engine_result do
    Map.update!(engine_result(), :plan_metadata, &Map.put(&1, :degraded?, true))
  end

  defp compare_engine_result do
    put_in(
      engine_result(),
      [
        :planned_source_requests,
        Access.at(0),
        :data_context,
        :source_contexts,
        :telemetry,
        :view
      ],
      "all_revisions"
    )
  end
end
