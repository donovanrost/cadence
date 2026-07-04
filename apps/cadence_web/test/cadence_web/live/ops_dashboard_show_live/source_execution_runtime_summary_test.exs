defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    PlannedSourceRequest,
    ResolveWarning,
    SourceWatermark
  }

  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary

  test "build summarizes degraded source execution outcomes and selections" do
    result = %DashboardResolveResult{
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          metadata: %{
            capability_provenance: %{
              source_binding_id: "binding-flight",
              data_source_id: "managed-questdb",
              realm: :flight,
              capability_posture: %{
                status: :fallback,
                requested_sampling: :latest,
                supported_sampling: [:latest],
                requested_products: [:link_rf_metric_history],
                supported_products: [:transport_bitrate_history],
                requested_time_axis: :generation_time,
                executed_time_axis: :receipt_time,
                supported_time_axes: [:receipt_time],
                fallbacks: [
                  %{
                    capability: :time_axis,
                    requested: :generation_time,
                    executed: :receipt_time,
                    reason: :unsupported_time_axis
                  }
                ]
              }
            }
          }
        },
        %PlannedSourceRequest{
          request_id: "req-limits",
          logical_source: :limits,
          source_dependencies: [
            %{
              logical_source: :telemetry,
              reason: :limit_latest_sample_input,
              products: [:latest_sample],
              sampling: %{mode: :latest}
            }
          ]
        }
      ],
      plan_metadata: %{
        source_selection_by_request_id: %{
          "req-telemetry" => %{
            selected_source_binding_id: "binding-flight",
            selected_data_source_id: "managed-questdb",
            strategy: :current_binding
          }
        },
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :stale, reasons: [:source_degraded]}
          }
        }
      },
      watermarks: [
        %SourceWatermark{
          logical_source: :telemetry,
          request_id: "req-telemetry",
          source_binding_id: "binding-flight",
          data_source_id: "managed-questdb",
          realm: :flight,
          dataset: "flight",
          confidence: :authoritative,
          freshness_state: :stale,
          complete_through: ~U[2026-06-17 12:00:00Z],
          latest_receipt_time: ~U[2026-06-17 12:00:01Z],
          sample_count: 42
        }
      ],
      dashboard_warnings: [
        %ResolveWarning{
          code: :source_degraded,
          severity: :error,
          details: %{
            source_request_id: "req-telemetry",
            circuit_state: :open,
            failure_count: 2,
            failure_threshold: 2,
            retry_after_ms: 60_000
          }
        }
      ]
    }

    assert %{
             actionable_count: 1,
             retryable_count: 1,
             degraded_count: 1,
             runtime_actions: %{wait_for_source_health: 1},
             operator_actions: %{inspect_source_health: 1},
             statuses: %{source_degraded: 1},
             severities: %{warning: 1}
           } = SourceExecutionRuntimeSummary.build(result)

    assert [
             %{
               request_id: "req-limits",
               request_logical_source: :limits,
               logical_source: :telemetry,
               reason: :limit_latest_sample_input,
               products: [:latest_sample],
               sampling: %{mode: :latest},
               upstream_request_id: "req-telemetry",
               upstream_status: :source_degraded,
               upstream_severity: :warning,
               upstream_runtime_action: :wait_for_source_health,
               upstream_operator_action: :inspect_source_health,
               upstream_cache_status: :stale,
               upstream_cache_reasons: [:source_degraded],
               upstream_source_binding_id: "binding-flight",
               upstream_data_source_id: "managed-questdb",
               upstream_realm: :flight,
               upstream_dataset: nil,
               upstream_degraded?: true,
               upstream_actionable?: true,
               upstream_retryable?: true,
               upstream_watermark_freshness_state: :stale,
               upstream_watermark_confidence: :authoritative,
               upstream_watermark_complete_through: ~U[2026-06-17 12:00:00Z],
               upstream_watermark_latest_receipt_time: ~U[2026-06-17 12:00:01Z],
               upstream_watermark_sample_count: 42
             }
           ] = SourceExecutionRuntimeSummary.build(result).source_dependencies

    assert %{
             "req-telemetry" => %{
               selected_source_binding_id: "binding-flight",
               selected_data_source_id: "managed-questdb",
               strategy: :current_binding
             }
           } = SourceExecutionRuntimeSummary.build(result).source_selections

    assert [
             %{
               request_id: "req-telemetry",
               logical_source: :telemetry,
               status: :fallback,
               requested_sampling: :latest,
               supported_sampling: [:latest],
               requested_products: [:link_rf_metric_history],
               supported_products: [:transport_bitrate_history],
               requested_time_axis: :generation_time,
               executed_time_axis: :receipt_time,
               supported_time_axes: [:receipt_time],
               source_binding_id: "binding-flight",
               data_source_id: "managed-questdb",
               realm: :flight
             }
           ] = SourceExecutionRuntimeSummary.build(result).capability_postures

    assert [
             %{
               request_id: "req-telemetry",
               logical_source: :telemetry,
               status: :source_degraded,
               severity: :warning,
               retryable?: true,
               actionable?: true,
               runtime_action: :wait_for_source_health,
               operator_action: :inspect_source_health
             }
           ] = SourceExecutionRuntimeSummary.build(result).degraded_outcomes

    assert [
             %{
               request_id: "req-telemetry",
               logical_source: :telemetry,
               status: :source_degraded,
               severity: :warning,
               retryable?: true,
               actionable?: true,
               runtime_action: :wait_for_source_health,
               operator_action: :inspect_source_health
             }
           ] = SourceExecutionRuntimeSummary.build(result).degraded_incidents
  end

  test "build returns an empty summary for missing engine results" do
    assert SourceExecutionRuntimeSummary.build(nil) == %{
             actionable_count: 0,
             retryable_count: 0,
             degraded_count: 0,
             source_incidents: [],
             degraded_incidents: [],
             degraded_outcomes: [],
             capability_postures: [],
             source_selections: %{},
             source_dependencies: [],
             runtime_actions: %{},
             operator_actions: %{},
             statuses: %{},
             severities: %{}
           }
  end
end
