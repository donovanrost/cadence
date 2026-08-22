defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryDegradedTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryFixtures

  test "build projects degraded outcomes and incidents" do
    summary =
      SourceExecutionRuntimeSummary.build(
        SourceExecutionRuntimeSummaryFixtures.degraded_source_result()
      )

    expected_degraded_source = %{
      request_id: "req-telemetry",
      logical_source: :telemetry,
      status: :source_degraded,
      severity: :warning,
      realm: :flight,
      data_source_id: "managed-questdb",
      source_binding_id: "binding-flight",
      retryable?: true,
      actionable?: true,
      runtime_action: :wait_for_source_health,
      operator_action: :inspect_source_health
    }

    assert [^expected_degraded_source] = summary.degraded_outcomes
    assert [^expected_degraded_source] = summary.degraded_incidents
  end
end
