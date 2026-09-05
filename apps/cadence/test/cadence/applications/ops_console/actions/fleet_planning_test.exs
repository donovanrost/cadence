defmodule Cadence.Applications.OpsConsole.Actions.FleetPlanningTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Applications.OpsConsole.Actions.FleetPlanning

  @organization_id "org-ops-fleet-actions"
  @mission_id "mission-ops-fleet-actions"

  setup do
    %{organization: organization} = persist_mission_scope(@organization_id, @mission_id)

    %{scope: scope(organization, :member)}
  end

  test "declares only the exact domain-backed Fleet Planning host actions" do
    assert FleetPlanning.bindings() == [
             {"fleet_planning", "refresh-planning"},
             {"fleet_planning_new", "create-fleet-run"},
             {"fleet_planning_policy", "save-policy"},
             {"fleet_planning_policy", "approve-policy"},
             {"fleet_planning_policy", "issue-grant"},
             {"fleet_planning_policy", "revoke-grant"},
             {"fleet_planning_run", "refresh-fleet-run"},
             {"fleet_planning_run", "repair-fleet-run"}
           ]
  end

  test "refresh-planning succeeds through the mission-scoped domain reads", %{scope: scope} do
    assert {:ok, result} = execute(scope, "fleet_planning", "refresh-planning", %{})

    assert result["missionId"] == @mission_id
    assert result["runCount"] == 0
    assert result["activePolicy"] == false
    assert FleetPlanning.result(result) == result
  end

  test "rejects a request whose mission parameter disagrees with the host context", %{
    scope: scope
  } do
    assert {:error, :scope_mismatch} =
             execute(scope, "fleet_planning", "refresh-planning", %{"mission_id" => "other"})
  end

  test "rejects unknown actions without dispatching", %{scope: scope} do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "unknown",
      params: %{}
    }

    assert {:error, :unsupported_application_action} =
             FleetPlanning.execute(
               scope,
               HostContext.mission(@mission_id),
               "fleet_planning",
               request
             )
  end

  test "rejects malformed bounded input", %{scope: scope} do
    assert {:error, :unsupported_application_action} =
             execute(scope, "fleet_planning", "refresh-planning", %{"unexpected" => true})
  end

  defp execute(scope, surface_id, action_id, params) do
    FleetPlanning.execute(
      scope,
      HostContext.mission(@mission_id),
      surface_id,
      %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: action_id,
        params: params
      }
    )
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "ops-fleet-actions-user-#{role}",
        email: "ops-fleet-actions-#{role}@example.test",
        display_name: "Ops Fleet Actions #{role}"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
