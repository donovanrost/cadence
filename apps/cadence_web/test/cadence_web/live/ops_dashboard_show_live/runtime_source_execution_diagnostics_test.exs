defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnosticsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics

  test "build names source execution counts, summaries, and drilldowns" do
    diagnostics = RuntimeSourceExecutionDiagnostics.build(source_summary())

    assert diagnostics.runtime_actions_text ==
             "refresh_source_result:1 wait_for_source_health:2"

    assert diagnostics.retryable_count == 3
    assert diagnostics.actionable_count == 2
    assert diagnostics.degraded_count == 2

    assert diagnostics.degraded_identities_text ==
             "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"

    assert diagnostics.degraded_actions_text ==
             "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health"

    assert diagnostics.capability_statuses_text == "fallback:1 native:1"

    assert diagnostics.capability_posture_text ==
             "telemetry:req-circuit:fallback:generation_time->receipt_time telemetry:req-native:native:generation_time->generation_time"

    assert diagnostics.degraded_summary == %{
             visible?: true,
             count: 2,
             headline: "Source execution degraded.",
             identity: "telemetry:req-circuit:source_degraded",
             status: "source_degraded",
             runtime_action: "wait_for_source_health",
             operator_action: "inspect_source_health",
             realm: "flight",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             request_id: "req-circuit"
           }

    assert [
             %{request_id: "req-circuit", status: "source_degraded"},
             %{request_id: "req-unavailable", status: "source_unavailable"}
           ] = diagnostics.degraded_drilldowns

    assert diagnostics.dependency_degraded_count == 1

    assert diagnostics.dependency_evidence_text ==
             "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"

    assert [
             %{
               request_id: "req-circuit",
               logical_source: "telemetry",
               status: "fallback",
               requested_products: "link_rf_metric_history",
               supported_products: "transport_bitrate_history",
               requested_time_axis: "generation_time",
               executed_time_axis: "receipt_time",
               supported_time_axes: "receipt_time",
               fallbacks: "time_axis:generation_time:receipt_time:unsupported_time_axis"
             },
             %{request_id: "req-native", status: "native"}
           ] = diagnostics.capability_postures

    assert [
             %{
               request_id: "req-limits",
               request_logical_source: "limits",
               logical_source: "telemetry",
               products: "latest_sample",
               reason: "limit_latest_sample_input",
               upstream_request_id: "req-circuit",
               upstream_status: "source_degraded",
               upstream_runtime_action: "wait_for_source_health",
               upstream_operator_action: "inspect_source_health",
               upstream_cache_status: "stale",
               upstream_cache_reasons: "source_degraded",
               upstream_source_binding_id: "binding-flight",
               upstream_data_source_id: "questdb-flight",
               upstream_realm: "flight",
               upstream_watermark_freshness_state: "stale",
               upstream_watermark_confidence: "authoritative",
               upstream_watermark_complete_through: "2026-06-17T12:00:00Z"
             }
           ] = diagnostics.dependency_evidence
  end

  test "maybe_degrade_refresh_status marks refresh degraded when source execution degraded" do
    refresh_status = %{status: "settled", reason: "accepted", visible_action: "accept_result"}

    assert RuntimeSourceExecutionDiagnostics.maybe_degrade_refresh_status(
             refresh_status,
             RuntimeSourceExecutionDiagnostics.build(source_summary())
           ) == %{
             refresh_status
             | status: "degraded",
               reason: "source_execution_degraded"
           }

    assert RuntimeSourceExecutionDiagnostics.maybe_degrade_refresh_status(
             refresh_status,
             RuntimeSourceExecutionDiagnostics.build(%{})
           ) == refresh_status
  end

  test "decision_audit_from_summary returns durable audit fields only when source execution exists" do
    assert RuntimeSourceExecutionDiagnostics.decision_audit_from_summary(%{}) == %{}

    assert RuntimeSourceExecutionDiagnostics.decision_audit_from_summary(source_summary()) == %{
             source_execution_retryable_count: 3,
             source_execution_actionable_count: 2,
             source_execution_degraded_count: 2,
             source_execution_status_summary: %{source_degraded: 1, source_unavailable: 1},
             source_execution_severity_summary: %{error: 1, warning: 1},
             source_execution_runtime_action_summary: %{
               refresh_source_result: 1,
               wait_for_source_health: 2
             },
             source_execution_operator_action_summary: %{inspect_source_health: 2},
             source_execution_degraded_identities: [
               "telemetry:req-circuit:source_degraded",
               "telemetry:req-unavailable:source_unavailable"
             ],
             source_execution_degraded_actions: [
               "telemetry:req-circuit:wait_for_source_health:inspect_source_health",
               "telemetry:req-unavailable:wait_for_source_health:inspect_source_health"
             ],
             source_capability_posture_summary: %{fallback: 1, native: 1},
             source_capability_posture_evidence: [
               "telemetry:req-circuit:fallback:generation_time->receipt_time",
               "telemetry:req-native:native:generation_time->generation_time"
             ],
             source_dependency_degraded_count: 1,
             source_dependency_evidence: [
               "limits:req-limits->telemetry:req-circuit:source_degraded:wait_for_source_health:stale"
             ]
           }
  end

  defp source_summary do
    %{
      runtime_actions: %{refresh_source_result: 1, wait_for_source_health: 2},
      retryable_count: 3,
      actionable_count: 2,
      degraded_count: 2,
      statuses: %{source_degraded: 1, source_unavailable: 1},
      severities: %{warning: 1, error: 1},
      operator_actions: %{inspect_source_health: 2},
      capability_postures: [
        %{
          request_id: "req-circuit",
          logical_source: :telemetry,
          status: :fallback,
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
        },
        %{
          request_id: "req-native",
          logical_source: :telemetry,
          status: :native,
          requested_time_axis: :generation_time,
          executed_time_axis: :generation_time,
          supported_time_axes: [:generation_time, :receipt_time]
        }
      ],
      source_dependencies: [
        %{
          request_id: "req-limits",
          request_logical_source: :limits,
          logical_source: :telemetry,
          reason: :limit_latest_sample_input,
          products: [:latest_sample],
          upstream_request_id: "req-circuit",
          upstream_status: :source_degraded,
          upstream_runtime_action: :wait_for_source_health,
          upstream_operator_action: :inspect_source_health,
          upstream_cache_status: :stale,
          upstream_cache_reasons: [:source_degraded],
          upstream_source_binding_id: "binding-flight",
          upstream_data_source_id: "questdb-flight",
          upstream_realm: :flight,
          upstream_degraded?: true,
          upstream_watermark_freshness_state: :stale,
          upstream_watermark_confidence: :authoritative,
          upstream_watermark_complete_through: ~U[2026-06-17 12:00:00Z]
        }
      ],
      degraded_incidents: [
        %{
          logical_source: :telemetry,
          request_id: "req-circuit",
          status: :source_degraded,
          runtime_action: :wait_for_source_health,
          operator_action: :inspect_source_health,
          realm: :flight,
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        %{
          logical_source: :telemetry,
          request_id: "req-unavailable",
          status: :source_unavailable,
          runtime_action: :wait_for_source_health,
          operator_action: :inspect_source_health,
          realm: :flight,
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        }
      ]
    }
  end
end
