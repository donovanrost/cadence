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
             {"fleet_planning_new", "validate-fleet-run"},
             {"fleet_planning_new", "create-fleet-run"},
             {"fleet_planning_policy", "validate-policy"},
             {"fleet_planning_policy", "save-policy"},
             {"fleet_planning_policy", "approve-policy"},
             {"fleet_planning_policy", "validate-grant"},
             {"fleet_planning_policy", "issue-grant"},
             {"fleet_planning_policy", "revoke-grant"},
             {"fleet_planning_run", "refresh-fleet-run"},
             {"fleet_planning_run", "repair-fleet-run"}
           ]
  end

  test "validates a fleet run without persisting it", %{scope: scope} do
    params = %{
      "fleet_run" => %{
        "horizon_start" => "2026-09-05T00:00:00Z",
        "horizon_end" => "2026-09-05T01:00:00Z",
        "include_recurring" => "false"
      }
    }

    assert {:ok,
            %{
              "surfaceId" => "fleet_planning_new",
              "actionId" => "validate-fleet-run",
              "valid" => true,
              "errors" => []
            }} = execute(scope, "fleet_planning_new", "validate-fleet-run", params)
  end

  test "rejects malformed fleet run validation input", %{scope: scope} do
    assert {:error, :fleet_planning_horizon_invalid} =
             execute(scope, "fleet_planning_new", "validate-fleet-run", %{
               "fleet_run" => %{
                 "horizon_start" => "not-a-datetime",
                 "horizon_end" => "2026-09-05T01:00:00Z",
                 "include_recurring" => "false"
               }
             })
  end

  test "validates policy and grant forms without persisting them", %{scope: scope} do
    assert {:ok, %{"actionId" => "validate-policy", "valid" => true}} =
             execute(scope, "fleet_planning_policy", "validate-policy", %{
               "policy" => policy_params()
             })

    assert {:ok, %{"actionId" => "validate-grant", "valid" => true}} =
             execute(scope, "fleet_planning_policy", "validate-grant", %{
               "grant" => %{
                 "service_identity_id" => "service-1",
                 "maximum_horizon_hours" => "24",
                 "maximum_contacts" => "10",
                 "maximum_execution_concurrency" => "2",
                 "valid_days" => "7",
                 "approval_reason" => "bounded operations"
               }
             })
  end

  test "rejects malformed policy validation input", %{scope: scope} do
    assert {:error, :invalid_fleet_policy_form} =
             execute(scope, "fleet_planning_policy", "validate-policy", %{
               "policy" => Map.put(policy_params(), "max_contacts", "not-an-integer")
             })
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

  defp policy_params do
    %{
      "max_horizon_hours" => "24",
      "requirement_concurrency" => "2",
      "provider_search_concurrency" => "2",
      "reuse_freshness_seconds" => "60",
      "max_contacts" => "10",
      "max_estimated_cost_micros" => "1000",
      "currency" => "USD",
      "critical_contact_reserve" => "0",
      "automation_mode" => "advisory",
      "execution_concurrency" => "1",
      "max_repair_attempts" => "0",
      "repair_horizon_hours" => "24",
      "automatic_submission" => "false",
      "distinct_provider_required" => "false",
      "distinct_station_required" => "false",
      "distinct_service_pool_required" => "false"
    }
  end
end
