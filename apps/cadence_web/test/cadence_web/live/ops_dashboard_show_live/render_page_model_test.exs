defmodule CadenceWeb.OpsDashboardShowLive.RenderPageModelTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DataBinding,
    Document,
    RenderWidget
  }

  alias CadenceWeb.OpsDashboardShowLive.{
    RenderGridModel,
    RenderPageModel,
    RenderPanelModel,
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

    assert model.toolbar_props ==
             assigns
             |> RenderToolbarModel.props()
             |> Map.merge(%{
               comparison_available?: false,
               comparison_open?: false,
               comparison_open_count: 0
             })

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

  defp degraded_engine_result do
    Map.update!(engine_result(), :plan_metadata, &Map.put(&1, :degraded?, true))
  end
end
