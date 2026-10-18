defmodule Cadence.Applications.OpsConsole.Actions.ContactPlanningTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactRequirements
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
    assert {"contact_requirement_new", "save"} in ContactPlanning.bindings()
    assert {"contact_plan_show", "execute-plan"} in ContactPlanning.bindings()
    refute {"contact_requirement_show", "toggle-opportunity"} in ContactPlanning.bindings()

    assert {:error, :unsupported_action} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_requirement_show",
               request("toggle-opportunity", %{"snapshot_id" => "snapshot-1"})
             )
  end

  test "save authorizes and persists the exact Contact Requirement domain result", %{
    scope: scope,
    host_context: host_context
  } do
    assert {:ok,
            %{
              "contactRequirementId" => requirement_id,
              "version" => 1,
              "contentSha256" => content_sha256
            }} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_requirement_new",
               request("save", %{"contact_requirement" => requirement_params()})
             )

    assert content_sha256 =~ ~r/\A[0-9a-f]{64}\z/

    assert {:ok, requirement, version} =
             ContactRequirements.fetch(@organization_id, @mission_id, requirement_id)

    assert requirement.contact_requirement_id == requirement_id
    assert version.service_direction == :downlink
    assert version.contact_intent == "payload_downlink"
  end

  test "rejects a request bound to another mission", %{scope: scope, host_context: host_context} do
    params = %{
      "mission_id" => @other_mission_id,
      "contact_requirement" => requirement_params()
    }

    assert {:error, :scope_mismatch} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_requirement_new",
               request("save", params)
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
               "contact_requirement_new",
               request("unknown-action", %{})
             )

    assert {:error, :malformed_input} =
             ContactPlanning.execute(
               scope,
               host_context,
               "contact_requirement_new",
               request("save", %{"contact_requirement" => %{"spacecraft_id" => self()}})
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

  defp requirement_params do
    %{
      "spacecraft_id" => @spacecraft_id,
      "contact_intent" => "payload_downlink",
      "earliest_start" => "2026-07-16T21:00:00",
      "latest_end" => "2026-07-17T04:00:00",
      "success_measure" => "minimum_data_volume",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "1000000000",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "allowed_providers" => "",
      "excluded_providers" => "",
      "allowed_stations" => "",
      "excluded_stations" => "",
      "rationale" => "Downlink before the next collection period"
    }
  end
end
