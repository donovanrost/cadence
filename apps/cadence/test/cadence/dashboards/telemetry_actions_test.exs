defmodule Cadence.Dashboards.TelemetryActionsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DataContext,
    DataLink,
    PlannedSourceRequest,
    ScopeContext,
    TelemetryActions
  }

  test "builds route-free telemetry explore actions from planned source context" do
    request = %PlannedSourceRequest{
      request_id: "req-telemetry",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      scope_context: ScopeContext.from_map(%{primary: %{kind: :spacecraft, ids: ["sc-1"]}}),
      time_context: %{mode: :range, from: ~U[2026-06-17 12:00:00Z], to: ~U[2026-06-17 12:05:00Z]},
      data_context:
        DataContext.from_map(%{
          realm: :flight,
          source_contexts: %{
            telemetry: %{
              data_source_id: "flight-questdb",
              source_binding_id: "flight-binding",
              view: :all_revisions
            }
          }
        })
    }

    assert [
             %DashboardAction{
               action_id: "dashboard-telemetry-explore-action",
               target: :telemetry_explore,
               kind: :invoke,
               route: nil,
               query: %{
                 "point_id" => "HK.counter",
                 "sample_id" => "sample-1",
                 "selected_time" => "2026-06-17T12:00:30Z",
                 "time_mode" => "range",
                 "from" => "2026-06-17T12:00:00Z",
                 "to" => "2026-06-17T12:05:00Z",
                 "realm" => "flight",
                 "data_view" => "all_revisions",
                 "logical_source" => "telemetry",
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "flight-binding"
               },
               source: :frame
             }
           ] =
             TelemetryActions.explore_actions(
               request,
               "HK.counter",
               [%{sample_id: "sample-1", receipt_time: ~U[2026-06-17 12:00:30Z]}],
               source: :frame
             )
  end

  test "builds telemetry explore actions from telemetry data links" do
    link = %DataLink{
      target: :telemetry_sample,
      target_id: "sample-1",
      context: %{
        logical_source: :telemetry,
        observable_id: "HK.counter",
        time: %{mode: :live},
        data: %{realm: :flight, view: :as_recorded, data_source_id: "flight-questdb"}
      }
    }

    assert %DashboardAction{
             target: :telemetry_explore,
             kind: :invoke,
             query: %{
               "point_id" => "HK.counter",
               "sample_id" => "sample-1",
               "time_mode" => "live",
               "realm" => "flight",
               "data_view" => "as_recorded",
               "logical_source" => "telemetry",
               "data_source_id" => "flight-questdb"
             },
             source: :data_link_panel
           } = TelemetryActions.explore_action_from_data_link(link)
  end

  test "preserves replay run identity in telemetry explore action queries" do
    link = %DataLink{
      target: :telemetry_sample,
      target_id: "sample-replay-1",
      context: %{
        logical_source: :telemetry,
        observable_id: "HK.counter",
        time: %{mode: :replay_run, replay_run_id: "replay-run-1"},
        data: %{
          realm: :replay,
          replay_run_id: "replay-run-1",
          data_source_id: "replay-questdb",
          source_binding_id: "replay-binding"
        }
      }
    }

    assert %DashboardAction{
             target: :telemetry_explore,
             query: %{
               "point_id" => "HK.counter",
               "sample_id" => "sample-replay-1",
               "time_mode" => "replay_run",
               "replay_run_id" => "replay-run-1",
               "realm" => "replay",
               "data_source_id" => "replay-questdb",
               "source_binding_id" => "replay-binding"
             }
           } = TelemetryActions.explore_action_from_data_link(link)
  end

  test "ignores non-telemetry data links" do
    assert is_nil(
             TelemetryActions.explore_action_from_data_link(%DataLink{
               target: :limit_event,
               target_id: "limit-event-1"
             })
           )
  end
end
