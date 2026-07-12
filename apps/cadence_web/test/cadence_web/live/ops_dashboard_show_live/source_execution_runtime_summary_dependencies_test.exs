defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryDependenciesTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryFixtures

  test "build projects upstream dependency status, cache, source identity, and watermark evidence" do
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
           ] =
             SourceExecutionRuntimeSummary.build(
               SourceExecutionRuntimeSummaryFixtures.degraded_source_result()
             ).source_dependencies
  end
end
