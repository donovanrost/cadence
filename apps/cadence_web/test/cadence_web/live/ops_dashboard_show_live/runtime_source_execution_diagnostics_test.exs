defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    Document,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCoordinator
  }

  alias Cadence.DataSources.SourceWatermark

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnostics

  test "build handles empty source execution summaries" do
    assert RuntimeDiagnostics.build(%{
             engine_result: nil,
             runtime_coordinator: RuntimeCoordinator.new(status: :idle),
             decisions: [],
             resolved?: true,
             invalidation: %{event_count: 0, artifact_count: 0, boundaries: %{}},
             last_invalidation: nil,
             runtime_invalidation_events: [],
             current_scope: %{organization_id: "org-1"},
             mission: %{mission_id: "mission-1"},
             document: %Document{dashboard_id: "dashboard-1"},
             runtime_context: %{time_mode: "live", data_realm: "flight"}
           }).source_execution_degraded_summary == %{visible?: false}
  end

  test "build exposes stale failed and circuit-open source decisions" do
    diagnostics =
      RuntimeDiagnostics.build(%{
        engine_result: source_decision_result(),
        runtime_coordinator: RuntimeCoordinator.new(status: :idle),
        decisions: [%{action: :accept_result, resolve_id: 1}],
        resolved?: true,
        invalidation: %{event_count: 0, artifact_count: 0, boundaries: %{}},
        last_invalidation: nil,
        runtime_invalidation_events: [],
        current_scope: %{organization_id: "org-1"},
        mission: %{mission_id: "mission-1"},
        document: %Document{dashboard_id: "dashboard-1"},
        runtime_context: %{time_mode: "live", data_realm: "flight"}
      })

    assert diagnostics.refresh_status == "degraded"
    assert diagnostics.refresh_reason == "source_execution_degraded"
    assert diagnostics.source_execution_retryable_count == 3
    assert diagnostics.source_execution_actionable_count == 2
    assert diagnostics.source_execution_degraded_count == 2

    assert diagnostics.source_execution_runtime_actions ==
             "refresh_source_result:1 wait_for_source_health:2"

    assert diagnostics.source_execution_degraded_identities ==
             "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"

    assert diagnostics.source_execution_degraded_actions ==
             "telemetry:req-circuit:wait_for_source_health:inspect_source_health telemetry:req-unavailable:wait_for_source_health:inspect_source_health"

    assert diagnostics.source_execution_degraded_summary == %{
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
             %{
               request_id: "req-circuit",
               logical_source: "telemetry",
               status: "source_degraded",
               runtime_action: "wait_for_source_health",
               operator_action: "inspect_source_health",
               realm: "flight",
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight"
             },
             %{
               request_id: "req-unavailable",
               logical_source: "telemetry",
               status: "source_unavailable",
               runtime_action: "wait_for_source_health",
               operator_action: "inspect_source_health",
               realm: "flight",
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight"
             }
           ] = diagnostics.source_execution_degraded_drilldowns

    assert diagnostics.cache_summary.evidence_state_summary == %{
             total: 3,
             resolved: 3,
             context_only: 0,
             missing: 0
           }

    assert Enum.any?(
             diagnostics.cache_summary.drilldowns,
             &(&1.request_id == "req-stale" and &1.status == "stale" and
                 &1.reasons == "source_degraded")
           )

    assert Enum.any?(
             diagnostics.cache_summary.drilldowns,
             &(&1.request_id == "req-circuit" and &1.incident_status == "source_degraded" and
                 &1.incident_evidence_target == "source_request" and
                 &1.incident_evidence_target_id == "req-circuit")
           )
  end

  defp source_decision_result do
    %DashboardResolveResult{
      dashboard_id: "dashboard-1",
      resolve_mode: :context_change,
      planned_source_requests: [
        source_request("req-stale"),
        source_request("req-unavailable"),
        source_request("req-circuit")
      ],
      watermarks: [
        source_watermark("req-stale"),
        source_watermark("req-unavailable"),
        source_watermark("req-circuit")
      ],
      plan_metadata: %{
        source_request_count: 3,
        executed_source_request_count: 2,
        skipped_source_request_count: 1,
        returned_frame_count: 0,
        cache: %{
          source_result_cache_by_request_id: %{
            "req-stale" => %{status: :stale, reasons: [:source_degraded]},
            "req-unavailable" => %{status: :disabled},
            "req-circuit" => %{status: :disabled}
          }
        }
      },
      dashboard_warnings: [
        source_warning(:source_unavailable, "req-unavailable"),
        source_warning(:source_degraded, "req-circuit", %{
          circuit_state: :open,
          failure_count: 2,
          failure_threshold: 2,
          retry_after_ms: 60_000
        })
      ]
    }
  end

  defp source_request(request_id) do
    %PlannedSourceRequest{
      request_id: request_id,
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{
        realm: :flight,
        source_contexts: %{
          telemetry: %{
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            view: :canonical
          }
        }
      },
      metadata: %{
        capability_provenance: %{
          source_binding_id: "binding-flight",
          data_source_id: "questdb-flight",
          realm: :flight,
          dataset: "flight"
        }
      }
    }
  end

  defp source_watermark(request_id) do
    %SourceWatermark{
      logical_source: :telemetry,
      request_id: request_id,
      source_binding_id: "binding-flight",
      data_source_id: "questdb-flight",
      realm: :flight,
      dataset: "flight",
      confidence: :authoritative,
      freshness_state: :fresh
    }
  end

  defp source_warning(code, request_id, extra_details \\ %{}) do
    %ResolveWarning{
      code: code,
      severity: warning_severity(code),
      details:
        Map.merge(
          %{
            source_request_id: request_id,
            logical_source: :telemetry,
            source_binding_id: "binding-flight",
            data_source_id: "questdb-flight",
            realm: :flight
          },
          extra_details
        )
    }
  end

  defp warning_severity(:source_degraded), do: :warning
  defp warning_severity(:source_unavailable), do: :error
end
