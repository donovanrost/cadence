defmodule Cadence.Dashboards.SourceIncidentTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveResult,
    EvidenceRef,
    PlannedSourceRequest,
    ResolveWarning,
    SourceIncident
  }

  alias Cadence.DataSources.SourceWatermark

  test "summarizes source incidents from watermarks, cache state, warnings, and execution outcomes" do
    result = %DashboardResolveResult{
      watermarks: [
        %SourceWatermark{
          logical_source: :telemetry,
          request_id: "req-telemetry",
          source_binding_id: "binding-flight",
          data_source_id: "managed-questdb",
          realm: :flight,
          confidence: :authoritative,
          freshness_state: :fresh,
          latest_receipt_time: ~U[2026-06-24 01:00:00Z],
          meta: %{
            source_health_event_id: "source-health-event-1",
            source_health_reason: :source_adapter_probe_unsupported,
            source_health_probe_kind: "adapter_unsupported",
            source_health_probe_message: "adapter does not support active probes",
            source_health_probe_metadata: %{"storage" => "questdb", "password" => "secret"}
          }
        }
      ],
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          observables: ["HK.counter"],
          data_context: %{realm: :flight},
          sampling: %{mode: :latest}
        }
      ],
      plan_metadata: %{
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :stale, reasons: [:source_degraded]}
          },
          frame_cache_by_placement: %{
            "placement-counter" => %{"req-telemetry" => %{status: :refresh}}
          }
        }
      },
      dashboard_warnings: [
        %ResolveWarning{
          code: :source_degraded,
          severity: :warning,
          details: %{
            source_request_id: "req-telemetry",
            circuit_state: :open
          }
        }
      ]
    }

    assert [
             %{
               incident_kind: :source_execution,
               incident_status: :source_degraded,
               logical_source: :telemetry,
               state: :fresh,
               request_id: "req-telemetry",
               source_binding_id: "binding-flight",
               data_source_id: "managed-questdb",
               source_health_event_id: "source-health-event-1",
               source_health_reason: :source_adapter_probe_unsupported,
               source_health_probe_kind: "adapter_unsupported",
               source_health_probe_message: "adapter does not support active probes",
               source_health_probe_metadata: %{"storage" => "questdb", "password" => "secret"},
               source_cache_status: :stale,
               source_cache: %{status: :stale, reasons: [:source_degraded]},
               frame_cache_status: :refresh,
               frame_cache: %{status: :refresh, statuses: [:refresh]},
               circuit_state: :open,
               execution_status: :source_degraded,
               execution_operator_action: :inspect_source_health,
               execution_runtime_action: :wait_for_source_health,
               execution_dashboard_degraded?: true,
               source_warning_code: :source_degraded,
               evidence_refs: [
                 %EvidenceRef{kind: :source_request, id: "req-telemetry", confidence: :direct},
                 %EvidenceRef{kind: :data_source, id: "managed-questdb", confidence: :direct},
                 %EvidenceRef{kind: :source_binding, id: "binding-flight", confidence: :direct}
               ],
               actions: [
                 %DashboardAction{target: :source_health},
                 %DashboardAction{target: :source_inventory}
               ]
             }
           ] = SourceIncident.summaries(result)
  end

  test "synthesizes unknown source incidents for planned requests without watermarks" do
    result = %DashboardResolveResult{
      watermarks: [],
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-limits",
          logical_source: :limits,
          data_context: %{
            realm: :rehearsal,
            data_source_id: "limits-projection",
            source_binding_id: "limits-binding"
          }
        }
      ]
    }

    assert [
             %{
               incident_kind: :source_execution,
               incident_status: :skipped,
               logical_source: :limits,
               state: :unknown,
               request_id: "req-limits",
               realm: :rehearsal,
               data_source_id: "limits-projection",
               source_binding_id: "limits-binding"
             }
           ] = SourceIncident.summaries(result)
  end

  test "builds execution details from source execution outcomes" do
    assert %{
             source_request_id: "req-telemetry",
             logical_source: :telemetry,
             source_execution_status: :source_degraded,
             source_execution_severity: :warning,
             source_execution_action: :inspect_source_health,
             source_execution_runtime_action: :wait_for_source_health,
             source_execution_actionable?: true,
             source_execution_retryable?: true,
             source_execution_dashboard_degraded?: true,
             source_execution_cache_status: :stale,
             source_execution_warning_codes: [:source_degraded],
             source_binding_id: "binding-flight",
             data_source_id: "flight-questdb",
             realm: :flight,
             dataset: "telemetry_samples"
           } =
             SourceIncident.execution_details(%{
               request_id: "req-telemetry",
               logical_source: :telemetry,
               status: :source_degraded,
               severity: :warning,
               operator_action: :inspect_source_health,
               runtime_action: :wait_for_source_health,
               actionable?: true,
               retryable?: true,
               dashboard_degraded?: true,
               cache_status: :stale,
               warning_codes: [:source_degraded],
               metadata: %{
                 source_binding_id: "binding-flight",
                 data_source_id: "flight-questdb",
                 realm: :flight,
                 dataset: "telemetry_samples"
               }
             })
  end

  test "enriches existing source warnings with execution details and actions" do
    result = %DashboardResolveResult{
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          metadata: %{
            capability_provenance: %{
              source_binding_id: "binding-flight",
              data_source_id: "managed-questdb",
              realm: :flight
            }
          }
        }
      ],
      plan_metadata: %{
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :stale, reasons: [:source_degraded]}
          }
        }
      },
      dashboard_warnings: [
        %ResolveWarning{
          code: :source_degraded,
          severity: :warning,
          details: %{
            source_request_id: "req-telemetry",
            circuit_state: :open
          }
        }
      ]
    }

    assert [
             %ResolveWarning{
               code: :source_degraded,
               details: %{
                 source_request_id: "req-telemetry",
                 source_execution_status: :source_degraded,
                 source_execution_action: :inspect_source_health,
                 source_execution_runtime_action: :wait_for_source_health,
                 circuit_state: :open,
                 actions: [
                   %DashboardAction{target: :source_health},
                   %DashboardAction{target: :source_inventory}
                 ]
               }
             }
           ] = SourceIncident.source_execution_warnings(result)
  end

  test "synthesizes source execution warnings for actionable outcomes without warnings" do
    result = %DashboardResolveResult{
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          metadata: %{
            capability_provenance: %{
              source_binding_id: "binding-flight",
              data_source_id: "managed-questdb",
              realm: :flight
            }
          }
        }
      ],
      plan_metadata: %{
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :source_execution_failed, reason: :timeout}
          }
        }
      },
      dashboard_warnings: []
    }

    assert [
             %ResolveWarning{
               code: :source_execution_failed,
               severity: :error,
               message:
                 "Telemetry source execution source_execution_failed; action inspect_source_failure.",
               evidence: [
                 %EvidenceRef{
                   kind: :source_request,
                   id: "req-telemetry",
                   source: :telemetry,
                   confidence: :direct
                 }
               ],
               details: %{
                 source_request_id: "req-telemetry",
                 logical_source: :telemetry,
                 source_execution_status: :source_execution_failed,
                 source_execution_action: :inspect_source_failure,
                 source_execution_runtime_action: :retry_source_execution,
                 actions: [
                   %DashboardAction{target: :source_health},
                   %DashboardAction{target: :source_inventory}
                 ]
               }
             }
           ] = SourceIncident.source_execution_warnings(result)
  end

  test "builds source incident actions from watermark, warning, and execution metadata" do
    actions =
      SourceIncident.actions(
        %{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          realm: :flight,
          data_source_id: "watermark-source"
        },
        %{
          details: %{
            source_binding_id: "warning-binding"
          }
        },
        %{
          metadata: %{
            data_source_id: "execution-source",
            dataset: "telemetry_samples"
          }
        }
      )

    assert [
             %DashboardAction{
               action_id: "dashboard-evidence-source-health",
               target: :source_health,
               source: :source_health,
               query: %{
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "data_source_id" => "execution-source",
                 "source_binding_id" => "warning-binding"
               }
             },
             %DashboardAction{
               action_id: "dashboard-evidence-source-inventory",
               target: :source_inventory,
               source: :source_health
             }
           ] = actions
  end

  test "adds execution source actions while preserving existing actions" do
    telemetry_action = %DashboardAction{
      action_id: "telemetry-warning-explore:req-telemetry:HK.counter",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{"point_id" => "HK.counter"},
      source: :warning
    }

    details =
      SourceIncident.put_execution_source_actions(
        %{actions: [telemetry_action]},
        %{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          status: :source_degraded,
          severity: :warning,
          operator_action: :inspect_source_health,
          runtime_action: :wait_for_source_health,
          actionable?: true,
          retryable?: true,
          dashboard_degraded?: true,
          metadata: %{data_source_id: "flight-questdb"}
        }
      )

    assert [
             %DashboardAction{target: :telemetry_explore},
             %DashboardAction{target: :source_health},
             %DashboardAction{target: :source_inventory}
           ] = details.actions
  end
end
