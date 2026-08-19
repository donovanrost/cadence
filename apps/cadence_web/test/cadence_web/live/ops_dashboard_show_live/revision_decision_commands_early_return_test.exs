defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionCommandsEarlyReturnTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionCommands

  @opts [dashboard_runtime_invalidation?: false]
  @scope %{organization_id: "org-dashboard-revision-command", user: %{id: "operator-revision"}}
  @mission %{mission_id: "mission-dashboard-revision-command"}

  test "requires an observation identity id" do
    assert {:error, {:missing_field, :observation_identity_id}} =
             RevisionDecisionCommands.apply_decision(
               %{"decision" => "mark_conflict"},
               @scope,
               @mission,
               @opts
             )
  end
end
