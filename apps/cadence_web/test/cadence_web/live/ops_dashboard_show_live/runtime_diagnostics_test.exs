defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    Document,
    RuntimeCoordinator
  }

  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnostics

  test "build includes invalidation, runtime, and source execution attributes" do
    diagnostics =
      RuntimeDiagnostics.build(%{
        engine_result: engine_result(),
        runtime_coordinator: RuntimeCoordinator.new(status: :idle),
        decisions: [
          %{action: :start_resolve, resolve_mode: :live_tick, reason: :tick},
          %{action: :start_resolve, resolve_mode: :context_change, reason: :runtime_invalidation},
          %{
            action: :cancel_obsolete,
            resolve_mode: :context_change,
            reason: :runtime_invalidation
          },
          %{action: :coalesce_tick, resolve_mode: :live_tick, reason: :tick},
          %{action: :noop, resolve_mode: :live_tick, reason: :edit_mode},
          %{action: :record_degradation, reason: :resolve_failed},
          %{action: :ignore_result, resolve_id: "obsolete-1", reason: :obsolete_resolve},
          %{action: :accept_result, resolve_id: 1}
        ],
        resolved?: true,
        invalidation: %{event_count: 0, artifact_count: 0, boundaries: %{}},
        last_invalidation: nil,
        runtime_invalidation_events: [],
        current_scope: %{organization_id: "org-1"},
        mission: %{mission_id: "mission-1"},
        document: %Document{dashboard_id: "dashboard-1"},
        runtime_context: %{time_mode: "live", data_realm: "flight"}
      })

    assert diagnostics.refresh_status == "settled"
    assert diagnostics.refresh_starts == "context_change:runtime_invalidation:1 live_tick:tick:1"
    assert diagnostics.refresh_cancellations == "context_change:runtime_invalidation:1"
    assert diagnostics.refresh_coalesced == "live_tick:tick:1"
    assert diagnostics.refresh_noops == "live_tick:edit_mode:1"
    assert diagnostics.refresh_failures == "resolve_failed:1"
    assert diagnostics.refresh_ignored == "obsolete_resolve:1"
    assert diagnostics.refresh_ignored_resolve_ids == "obsolete-1"
    assert diagnostics.canceled_resolve_count == 1
    assert diagnostics.failed_resolve_count == 1

    assert diagnostics.cache_summary == %{
             visible?: true,
             classification: "stale",
             plan: "hit",
             source: "hit stale",
             frame: "miss",
             headline: "Dashboard encountered stale runtime cache entries.",
             drilldowns: RuntimeCacheDiagnostics.drilldowns(engine_result()),
             evidence_state_summary: %{total: 3, resolved: 0, context_only: 3, missing: 0}
           }

    assert [
             %{
               layer: "source",
               status: "stale",
               request_id: "req-1",
               logical_source: "telemetry",
               observables: "HK.counter",
               realm: "flight",
               data_source_id: "questdb-flight",
               source_binding_id: "flight-binding",
               reasons: "source_degraded",
               fingerprint: "source-fp-1"
             }
             | _rest
           ] = diagnostics.cache_summary.drilldowns

    assert diagnostics.refresh_reason == "accepted"
    assert diagnostics.visible_refresh_action == "accept_result"

    assert Enum.any?(
             diagnostics.runtime_rows,
             &(&1 == %{label: "Ignored result resolve ids", value: "obsolete-1"})
           )

    assert Enum.any?(
             diagnostics.runtime_rows,
             &(&1 == %{label: "Refresh coalesced", value: "live_tick:tick:1"})
           )

    assert Enum.any?(
             diagnostics.runtime_rows,
             &(&1 == %{label: "Refresh noops", value: "live_tick:edit_mode:1"})
           )

    assert Enum.any?(
             diagnostics.runtime_rows,
             &(&1 == %{label: "Refresh failures", value: "resolve_failed:1"})
           )

    assert diagnostics.invalidation_event_count == 0
    assert diagnostics.invalidation_boundary_summary == "-"
    assert diagnostics.source_execution_runtime_actions == "-"
    assert diagnostics.source_execution_degraded_summary == %{visible?: false}
    assert diagnostics.source_execution_degraded_drilldowns == []
    assert Enum.any?(diagnostics.engine_rows, &(&1 == %{label: "Plan cache", value: "hit"}))
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
          source_result_cache_by_request_id: %{
            "req-1" => %{
              status: :stale,
              reasons: [:source_degraded],
              key: %{
                fingerprint: "source-fp-1",
                parts: %{
                  request: %{
                    request_id: "req-1",
                    logical_source: :telemetry,
                    observables: ["HK.counter"]
                  },
                  source_binding: %{binding_id: "flight-binding", realm: :flight},
                  data_source: %{data_source_id: "questdb-flight"}
                }
              }
            },
            "req-2" => %{
              status: :hit,
              key: %{
                fingerprint: "source-fp-2",
                parts: %{
                  request: %{
                    request_id: "req-2",
                    logical_source: :limits,
                    observables: ["HK.counter"]
                  },
                  source_binding: %{binding_id: "flight-limits", realm: :flight},
                  data_source: %{data_source_id: "limits-store"}
                }
              }
            }
          },
          frame_cache_by_placement: %{
            "placement-1" => %{
              "req-1" => %{
                status: :miss,
                source_result_cache_status: :stale,
                key: %{
                  fingerprint: "frame-fp-1",
                  parts: %{
                    source_result_request: %{
                      request_id: "req-1",
                      logical_source: :telemetry,
                      observables: ["HK.counter"]
                    },
                    source_result_binding: %{binding_id: "flight-binding", realm: :flight},
                    source_result_data_source: %{data_source_id: "questdb-flight"}
                  }
                }
              }
            }
          }
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
        }
      ]
    }
  end
end
