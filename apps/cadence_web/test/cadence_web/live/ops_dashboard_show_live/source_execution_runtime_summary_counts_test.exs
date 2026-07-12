defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryCountsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryFixtures

  test "build summarizes degraded source execution counts and actions" do
    assert %{
             actionable_count: 1,
             retryable_count: 1,
             degraded_count: 1,
             runtime_actions: %{wait_for_source_health: 1},
             operator_actions: %{inspect_source_health: 1},
             statuses: %{source_degraded: 1},
             severities: %{warning: 1}
           } =
             SourceExecutionRuntimeSummary.build(
               SourceExecutionRuntimeSummaryFixtures.degraded_source_result()
             )
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
