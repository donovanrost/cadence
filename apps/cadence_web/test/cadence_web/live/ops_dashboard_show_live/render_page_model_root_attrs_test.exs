defmodule CadenceWeb.OpsDashboardShowLive.RenderPageModelRootAttrsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{ComparisonReviewQueue, DataBinding, Document}

  alias CadenceWeb.OpsDashboardShowLive.{
    RenderRootAssigns,
    RenderRootAttrs
  }

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

  defp empty_review_queue do
    ComparisonReviewQueue.open_summary([])
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
