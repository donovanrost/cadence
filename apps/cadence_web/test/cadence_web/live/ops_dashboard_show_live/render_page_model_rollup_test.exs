defmodule CadenceWeb.OpsDashboardShowLive.RenderPageModelRollupTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    Document,
    Field,
    Frame,
    PlacementFrames,
    RenderWidget
  }

  alias Cadence.DataSources.DataBinding

  alias CadenceWeb.OpsDashboardShowLive.RenderPageModel

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
    assert model.comparison_inspector_open? == false
    assert model.toolbar_props.comparison_available? == true
    assert model.toolbar_props.comparison_open? == false
    assert model.toolbar_props.comparison_open_count == 1
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

  test "opens the page-local comparison inspector only in viewer mode" do
    base_assigns = %{
      dashboard_data_view: "all_revisions",
      dashboard_compare_data_view: "canonical",
      comparison_inspector_open?: true,
      dashboard_render_items: [render_item("placement-1")],
      dashboard_engine_frames_by_placement: %{"placement-1" => scalar_frames(42)},
      dashboard_compare_engine_frames_by_placement: %{"placement-1" => scalar_frames(40)}
    }

    viewer_model = base_assigns |> assigns() |> RenderPageModel.build()

    assert viewer_model.comparison_inspector_open? == true
    assert viewer_model.toolbar_props.comparison_open? == true

    editor_model =
      base_assigns
      |> Map.put(:edit_mode?, true)
      |> assigns()
      |> RenderPageModel.build()

    assert editor_model.comparison_inspector_open? == false
    assert editor_model.toolbar_props.comparison_open? == false
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
end
