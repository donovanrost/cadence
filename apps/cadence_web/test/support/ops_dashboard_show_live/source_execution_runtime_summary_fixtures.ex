defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryFixtures do
  @moduledoc false

  alias Cadence.Dashboards.{DashboardResolveResult, PlannedSourceRequest, ResolveWarning}

  alias Cadence.DataSources.SourceWatermark

  def degraded_source_result do
    %DashboardResolveResult{
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
  end
end
