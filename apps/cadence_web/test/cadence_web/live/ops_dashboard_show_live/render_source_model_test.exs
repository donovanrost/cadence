defmodule CadenceWeb.OpsDashboardShowLive.RenderSourceModelTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardResolveResult, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.RenderSourceModel

  test "dashboard_warning_props prepares warning payload" do
    props =
      %{dashboard_engine_result: %{plan_metadata: %{degraded?: true}}}
      |> RenderSourceModel.dashboard_warning_props()

    assert props == %{warnings: [], degraded?: true}
  end

  test "props prepares dashboard source props from one source context" do
    props =
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_warning_summaries: [%{code: :assigned_warning}],
        dashboard_degraded?: true,
        dashboard_source_health_summaries: [%{source_health_event_id: "health-1"}],
        dashboard_source_selection_summaries: [%{request_id: "req-1"}]
      }
      |> RenderSourceModel.props()

    assert props == %{
             dashboard_warning_props: %{
               warnings: [%{code: :assigned_warning}],
               degraded?: true
             },
             source_health_props: %{health: [%{source_health_event_id: "health-1"}]},
             source_selection_props: %{
               mission_id: "mission-1",
               selections: [%{request_id: "req-1"}]
             }
           }
  end

  test "dashboard_warning_props summarizes operational stale warnings" do
    warning = %ResolveWarning{
      code: :stale_data,
      severity: :warning,
      scope: :dashboard,
      message: "Operational observable data is stale",
      details: %{
        logical_source: :operational_observables,
        supported_capability: :command_queue_depth,
        observable_ids: ["commanding.queue_depth"],
        frame_ids: ["ops-request-1:command_queue_depth"]
      }
    }

    props =
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_engine_result: %DashboardResolveResult{
          dashboard_warnings: [warning],
          plan_metadata: %{degraded?: true}
        }
      }
      |> RenderSourceModel.dashboard_warning_props()

    assert props.degraded?

    assert [
             %{
               code: :stale_data,
               code_text: "stale_data",
               severity: :warning,
               severity_text: "warning",
               message: "Operational observable data is stale",
               details: details
             }
           ] = props.warnings

    assert details.logical_source == :operational_observables
    assert details.supported_capability == :command_queue_depth
    assert details.observable_ids == ["commanding.queue_depth"]
  end

  test "dashboard_warning_props summarizes incomplete limit evaluation with selected clock" do
    warning = %ResolveWarning{
      code: :incomplete_limit_evaluation,
      severity: :warning,
      scope: :dashboard,
      message:
        "Some telemetry samples have no active complete limit definition for recomputation",
      details: %{
        observable_id: "HK.counter",
        requested_semantics_mode: :recomputed,
        selected_limit_clock: %{
          observed: :limit_event_receipt_time,
          requested_time_axis: :receipt_time,
          requested_time_mode: "archive"
        },
        missing_sample_ids: ["sample-missing"],
        unresolved_capability: :target_limit_definition_intervals,
        source_request_id: "limits-request-1"
      }
    }

    props =
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_engine_result: %DashboardResolveResult{
          dashboard_warnings: [warning],
          plan_metadata: %{degraded?: true}
        }
      }
      |> RenderSourceModel.dashboard_warning_props()

    assert props.degraded?

    assert [
             %{
               code: :incomplete_limit_evaluation,
               code_text: "incomplete_limit_evaluation",
               label: "Incomplete limit analysis",
               message:
                 "Some telemetry samples have no active complete limit definition for recomputation",
               detail_rows: detail_rows
             }
           ] = props.warnings

    assert %{label: "Observable", value: "HK.counter"} in detail_rows
    assert %{label: "Limit mode", value: "recomputed"} in detail_rows
    assert %{label: "Missing samples", value: "sample-missing"} in detail_rows

    assert %{
             label: "Selected clock",
             value:
               "observed=limit_event_receipt_time requested_time_axis=receipt_time requested_time_mode=archive"
           } in detail_rows
  end

  test "source_health_props prepares source health payload" do
    assert RenderSourceModel.source_health_props(%{dashboard_engine_result: nil}) == %{health: []}
  end

  test "source_selection_props prepares dashboard source selection payload" do
    props =
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_engine_result: %DashboardResolveResult{
          plan_metadata: %{
            source_selection_by_request_id: %{
              "req-telemetry" => %{
                logical_source: :telemetry,
                strategy: :current_binding,
                selected_source_binding_id: "binding-flight",
                selected_data_source_id: "questdb-flight",
                candidates: [
                  %{
                    binding_id: "binding-flight",
                    data_source_id: "questdb-flight",
                    decision: :selected,
                    reasons: []
                  }
                ]
              }
            }
          }
        }
      }
      |> RenderSourceModel.source_selection_props()

    assert props.mission_id == "mission-1"

    assert %{
             selections: [
               %{
                 request_id: "req-telemetry",
                 logical_source_text: "Telemetry",
                 selected_binding_id: "binding-flight",
                 selected_data_source_id: "questdb-flight",
                 state: :selected
               }
             ]
           } = props
  end
end
