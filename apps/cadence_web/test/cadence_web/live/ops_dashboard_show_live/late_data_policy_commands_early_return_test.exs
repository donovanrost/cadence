defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommandsEarlyReturnTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommands

  @opts [dashboard_runtime_invalidation?: false]
  @scope %{organization_id: "org-dashboard-late-policy", user: %{id: "operator-late"}}
  @mission %{mission_id: "mission-dashboard-late-policy"}

  test "requires a decision" do
    assert {:error, {:missing_field, :decision}} =
             LateDataPolicyCommands.record_decision(%{}, @scope, @mission, @opts)
  end

  test "requires an explicit execution mode" do
    assert {:error, {:missing_field, :execution_mode}} =
             LateDataPolicyCommands.record_decision(
               %{"decision" => "accept"},
               @scope,
               @mission,
               @opts
             )
  end

  test "rejects unsupported execution modes" do
    assert {:error, {:unsupported_late_data_policy_execution_mode, "silent_fallback"}} =
             LateDataPolicyCommands.record_decision(
               %{"decision" => "accept", "execution_mode" => "silent_fallback"},
               @scope,
               @mission,
               @opts
             )
  end
end
