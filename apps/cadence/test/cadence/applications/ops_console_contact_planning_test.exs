defmodule Cadence.Applications.OpsConsole.Actions.ContactPlanningTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.OpportunityCapability
  alias Cadence.Spacecraft

  @organization_id "org-ops-contact-planning-actions"
  @mission_id "mission-ops-contact-planning-actions"
  @other_mission_id "mission-ops-contact-planning-other"
  @spacecraft_id "spacecraft-ops-contact-planning-actions"

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @organization_id,
               Spacecraft.new(%{
                 spacecraft_id: @spacecraft_id,
                 mission_id: mission.mission_id,
                 display_name: "Contact Action Testcraft"
               })
             )

    user =
      User.new(%{
        user_id: "ops-contact-planning-action-user",
        email: "ops-contact-planning-action@example.test",
        display_name: "Ops Contact Action User"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: :member
      })

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    %{scope: scope, host_context: HostContext.mission(@mission_id)}
  end

  test "bindings expose exact server-backed contact actions and omit socket selection", %{
    scope: scope,
    host_context: host_context
  } do
    assert {"contact_plan_show", "execute-plan"} in ContactPlanning.bindings()
    refute Enum.any?(ContactPlanning.bindings(), &match?({"contact_requirement_" <> _, _}, &1))

    assert {:error, :unsupported_action} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_requirement_new",
               request("save", %{"contact_requirement" => %{}})
             )
  end

  test "rejects a request bound to another mission", %{scope: scope, host_context: host_context} do
    params = %{
      "mission_id" => @other_mission_id,
      "contact_search" => %{"spacecraft_id" => @spacecraft_id}
    }

    assert {:error, :scope_mismatch} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_schedule",
               request("validate", params)
             )
  end

  test "rejects tampered and cross-scope reserve capabilities", %{
    scope: scope,
    host_context: host_context
  } do
    foreign_token =
      OpportunityCapability.sign(%{
        "organization_id" => @organization_id,
        "mission_id" => @other_mission_id,
        "spacecraft_id" => @spacecraft_id,
        "route_key" => "route-1",
        "route" => %{},
        "opportunity" => %{"id" => "opportunity-1"}
      })

    assert {:error, :opportunity_scope_mismatch} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_schedule",
               request("reserve", %{"token" => foreign_token})
             )

    assert {:error, :invalid_opportunity_capability} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_schedule",
               request("reserve", %{"token" => foreign_token <> "tampered"})
             )
  end

  test "rejects unknown and malformed requests without dispatch", %{
    scope: scope,
    host_context: host_context
  } do
    assert {:error, :unsupported_action} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_schedule",
               request("unknown-action", %{})
             )

    assert {:error, :malformed_input} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_schedule",
               request("validate", %{"contact_search" => %{"spacecraft_id" => self()}})
             )
  end

  defp request(action_id, params) do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action_id,
      params: params
    }
  end
end
