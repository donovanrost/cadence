defmodule CadenceWeb.OpsDashboardShowLive.DashboardPageSummaryModelTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias CadenceWeb.OpsDashboardShowLive.DashboardPageSummaryModel

  test "props builds dashboard health, comparison workflow, preset, and root attrs together" do
    review_queue = %{
      count: 1,
      count_text: "1",
      requests: [%{dashboard_lifecycle_event_id: "review-1"}],
      request_ids: ["review-1"],
      request_ids_attr: "review-1",
      placement_ids: ["placement-2"],
      placements_attr: "placement-2"
    }

    props =
      DashboardPageSummaryModel.props(
        %{
          current_scope: %{organization_id: "org-1"},
          current_mission: %{mission_id: "mission-1"},
          dashboard_document: %{dashboard_id: "dashboard-1"},
          dashboard_data_realms: ["flight"],
          dashboard_data_bindings: [],
          dashboard_data_realm: "flight",
          dashboard_data_view: "all_revisions",
          dashboard_compare_data_view: "canonical",
          dashboard_time_mode: "archive",
          dashboard_time_from: "2026-06-26T12:00:00Z",
          dashboard_time_to: "2026-06-26T12:05:00Z",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_source_id: "questdb-flight",
          dashboard_source_binding_id: "binding-flight",
          dashboard_limit_mode: "observed",
          dashboard_comparison_review_queue: review_queue,
          dashboard_investigation_presets: [%{preset_id: "saved-preset-1"}],
          dashboard_comparison_decision_events: [
            comparison_decision_event("placement-1",
              decision_event_id: "decision-event-1",
              decision: :accept_primary,
              decision_reason: "operator_reviewed"
            )
          ]
        },
        [
          widget_item("placement-1", "Temperature", :ready, :fresh, "increased"),
          widget_item("placement-2", "Pressure", :ready, :unavailable, "missing")
        ],
        "/missions/mission-1/ops/dashboards/dashboard-1?source_binding_id=binding-flight",
        %{dashboard_id: "dashboard-1"}
      )

    assert props.dashboard_health.state == :blocked
    assert props.dashboard_health.snapshot["organization_id"] == "org-1"
    assert props.dashboard_health.snapshot["mission_id"] == "mission-1"
    assert props.dashboard_health.snapshot["dashboard_id"] == "dashboard-1"

    assert props.dashboard_health.snapshot["runtime_context"] == %{
             "realm" => "flight",
             "data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "time_mode" => "archive",
             "time_from" => "2026-06-26T12:00:00Z",
             "time_to" => "2026-06-26T12:05:00Z",
             "replay_run_id" => "replay-1",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "limit_mode" => "observed"
           }

    assert props.comparison_rollup.visible? == true
    assert props.comparison_rollup.handled_count == 1
    assert props.comparison_rollup.open_count == 1

    assert props.comparison_rollup.workflow_groups == [
             %{
               key: "open",
               label: "Open findings",
               count: 1,
               placement_ids: "placement-2",
               items: [
                 %{
                   placement_id: "placement-2",
                   widget_id: "widget-placement-2",
                   title: "Pressure",
                   state: "missing",
                   label: "missing",
                   detail: "Pressure missing",
                   primary_view: "all_revisions",
                   compare_view: "canonical",
                   primary_count: 1,
                   compare_count: 0,
                   delta: nil,
                   primary_sample_id: nil,
                   compare_sample_id: nil,
                   primary_data_management: nil,
                   compare_data_management: nil,
                   primary_data_link: nil,
                   compare_data_link: nil,
                   decision_status: "unhandled",
                   handled?: false
                 }
               ]
             },
             %{
               key: "handled",
               label: "Handled findings",
               count: 1,
               placement_ids: "placement-1",
               items: [
                 %{
                   placement_id: "placement-1",
                   widget_id: "widget-placement-1",
                   title: "Temperature",
                   state: "increased",
                   label: "increased",
                   detail: "Temperature increased",
                   primary_view: "all_revisions",
                   compare_view: "canonical",
                   primary_count: 1,
                   compare_count: 1,
                   delta: nil,
                   primary_sample_id: nil,
                   compare_sample_id: nil,
                   primary_data_management: nil,
                   compare_data_management: nil,
                   primary_data_link: nil,
                   compare_data_link: nil,
                   decision_status: "applied",
                   handled?: true,
                   decision_event_id: "decision-event-1",
                   decision: "accept_primary",
                   decision_reason: "operator_reviewed",
                   decision_occurred_at: ~U[2026-06-26 12:01:00Z],
                   decision_authority: "comparison"
                 }
               ]
             }
           ]

    assert props.comparison_preset["schema"] == "dashboard_comparison_investigation_preset.v1"
    assert props.comparison_preset["comparison"]["open_count"] == 1
    assert props.open_review_summary == review_queue
    assert props.comparison_presets == [%{preset_id: "saved-preset-1"}]
    assert props.root_attrs["data-dashboard-health-state"] == "blocked"
    assert props.root_attrs["data-dashboard-comparison-handled"] == 1
    assert props.root_attrs["data-dashboard-comparison-open-placements"] == "placement-2"
  end

  test "props defaults absent review queue and missing widgets to empty summaries" do
    props =
      DashboardPageSummaryModel.props(
        %{dashboard_comparison_review_queue: nil},
        nil,
        "/missions/mission-1/ops/dashboards/dashboard-1",
        nil
      )

    assert props.open_review_summary == ComparisonReviewQueue.open_summary([])
    assert props.dashboard_health.visible? == false
    assert props.dashboard_health.state == :ready
    assert props.comparison_rollup.visible? == false
    assert props.comparison_preset == nil
    assert props.comparison_presets == []
    assert props.root_attrs["data-dashboard-health-state"] == "ready"
    assert props.root_attrs["data-dashboard-comparison-widgets"] == 0
  end

  defp widget_item(placement_id, title, lifecycle_state, source_state, comparison_state) do
    %{
      item: %{
        placement_id: placement_id,
        widget: %{widget_id: "widget-#{placement_id}", title: title}
      },
      props: %{
        data: %{
          lifecycle_state: lifecycle_state,
          source_status: %{state: source_state}
        },
        warnings: [],
        comparison_summary: %{
          state: comparison_state,
          label: comparison_state,
          title: "#{title} #{comparison_state}",
          primary_view: "all_revisions",
          compare_view: "canonical",
          primary_count: 1,
          compare_count: if(comparison_state == "missing", do: 0, else: 1)
        }
      }
    }
  end

  defp comparison_decision_event(placement_id, overrides) do
    Map.merge(
      %{
        decision_event_id: "decision-event-#{placement_id}",
        decision: :mark_conflict,
        decision_reason: "dashboard_comparison_finding",
        occurred_at: ~U[2026-06-26 12:01:00Z],
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
  end
end
