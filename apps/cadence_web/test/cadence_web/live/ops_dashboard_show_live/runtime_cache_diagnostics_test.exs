defmodule CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnosticsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnostics

  test "summary classifies cache state and includes evidence totals" do
    assert RuntimeCacheDiagnostics.summary(engine_result()) == %{
             visible?: true,
             classification: "stale",
             plan: "hit",
             source: "hit stale",
             frame: "miss",
             headline: "Dashboard encountered stale runtime cache entries.",
             drilldowns: RuntimeCacheDiagnostics.drilldowns(engine_result()),
             evidence_state_summary: %{total: 3, resolved: 0, context_only: 3, missing: 0}
           }

    fresh_result =
      put_in(engine_result().plan_metadata.cache, %{
        plan_cache: %{status: :miss},
        source_result_cache_by_request_id: %{"req-1" => %{status: :refresh}},
        frame_cache_by_placement: %{"placement-1" => [%{status: :miss}]}
      })

    reused_result =
      put_in(engine_result().plan_metadata.cache, %{
        plan_cache: %{status: :hit},
        source_result_cache_by_request_id: %{"req-1" => %{status: :hit}},
        frame_cache_by_placement: %{"placement-1" => [%{status: :hit}]}
      })

    bypassed_result = put_in(engine_result().plan_metadata.cache, %{})

    assert RuntimeCacheDiagnostics.summary(fresh_result).classification == "fresh"
    assert RuntimeCacheDiagnostics.summary(reused_result).classification == "reused"
    assert RuntimeCacheDiagnostics.summary(bypassed_result).classification == "bypassed"
    assert RuntimeCacheDiagnostics.summary(nil) == %{visible?: false}
  end

  test "drilldowns include source and frame provenance" do
    assert [
             %{
               layer: "source",
               evidence_id: "source:req-1",
               status: "stale",
               request_id: "req-1",
               placement_id: "-",
               logical_source: "telemetry",
               observables: "HK.counter",
               data_source_id: "questdb-flight",
               source_binding_id: "flight-binding",
               reasons: "source_degraded",
               fingerprint: "source-fp-1",
               evidence_state: "context_only"
             },
             %{
               layer: "frame",
               evidence_id: "frame:req-1:placement-1",
               status: "miss",
               request_id: "req-1",
               placement_id: "placement-1",
               logical_source: "telemetry",
               observables: "HK.counter",
               data_source_id: "questdb-flight",
               source_binding_id: "flight-binding",
               source_result_cache_status: "stale",
               evidence_state: "context_only"
             },
             %{
               layer: "source",
               evidence_id: "source:req-2",
               status: "hit",
               request_id: "req-2"
             }
           ] = RuntimeCacheDiagnostics.drilldowns(engine_result())
  end

  test "drilldowns and audit include source incident evidence" do
    source_incidents = [
      %{
        request_id: "req-1",
        incident_status: :source_degraded,
        incident_status_text: "source_degraded",
        incident_title: "Source Execution",
        incident_message: "Source execution source_degraded; action wait_for_refresh.",
        execution_severity_text: "warning",
        execution_operator_action_text: "wait_for_refresh",
        execution_runtime_action_text: "refresh_source_result",
        execution_actionable?: false,
        execution_retryable?: true,
        evidence: [
          %{
            kind: :source_health_event,
            kind_text: "source health event",
            id: "source-health-event-1",
            observed_at_text: "2026-06-25T12:00:00Z"
          }
        ]
      }
    ]

    assert [
             %{
               request_id: "req-1",
               incident_status: "source_degraded",
               incident_status_text: "source_degraded",
               incident_title: "Source Execution",
               incident_message: "Source execution source_degraded; action wait_for_refresh.",
               incident_severity: "warning",
               incident_operator_action: "wait_for_refresh",
               incident_runtime_action: "refresh_source_result",
               incident_actionable?: "false",
               incident_retryable?: "true",
               incident_evidence_target: "source_health_event",
               incident_evidence_target_id: "source-health-event-1",
               incident_evidence_kind_text: "source health event",
               incident_evidence_observed_at: "2026-06-25T12:00:00Z",
               evidence_state: "resolved"
             }
             | _rest
           ] = RuntimeCacheDiagnostics.drilldowns(engine_result(), source_incidents)

    assert RuntimeCacheDiagnostics.evidence_state_summary(
             RuntimeCacheDiagnostics.drilldowns(engine_result(), source_incidents)
           ) == %{total: 3, resolved: 2, context_only: 1, missing: 0}

    assert %{
             source_cache_evidence_state_summary: %{
               total: 3,
               resolved: 2,
               context_only: 1,
               missing: 0
             },
             source_cache_evidence_target_ids: ["source_health_event:source-health-event-1"],
             source_cache_evidence_request_ids: ["req-1", "req-2"]
           } =
             RuntimeCacheDiagnostics.source_cache_evidence_audit(
               engine_result(),
               source_incidents
             )

    assert RuntimeCacheDiagnostics.source_cache_evidence_audit(nil, source_incidents) == %{}
  end

  defp engine_result do
    %{
      resolve_mode: :context_change,
      plan_metadata: %{
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
