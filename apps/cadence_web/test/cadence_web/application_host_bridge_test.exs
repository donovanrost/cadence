defmodule CadenceWeb.ApplicationHostBridgeTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{
    ActionDefinition,
    ActionRequest,
    ApplicationDefinition,
    HostContext,
    SurfaceDefinition
  }

  alias Cadence.Auth.Scope
  alias CadenceWeb.{ApplicationHostBridge, TestFixtures}

  @now "2026-09-03T12:00:00Z"

  test "rejects recursively oversized query input before provider dispatch" do
    params = %{"params" => Enum.to_list(1..101)}

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationHostBridge.query(%Scope{}, %{}, params)
  end

  test "rejects invalid action scalar input before provider dispatch" do
    params = %{"input" => %{"value" => self()}}

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationHostBridge.action(%Scope{}, %{}, params, "bridge-test-key")
  end

  test "rejects mismatched action scopes" do
    third_party = %ApplicationDefinition{
      application_key: "third_party",
      version: 1,
      display_name: "Third Party",
      description: "Third party",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:organization, :mission]
    }

    organization_surface = %SurfaceDefinition{
      surface_id: "organization_surface",
      version: 1,
      purpose: :configuration,
      scope: :organization,
      placement: :application_workspace,
      data_contract: %{query_id: "third_party.organization", version: 1},
      renderer: {:trusted, "third_party.organization"}
    }

    mission_action = %ActionDefinition{
      action_id: "third_party_action",
      version: 1,
      intent: :configuration,
      scope: :mission,
      required_permission: "operate_mission",
      effect: :durable,
      execution: :immediate
    }

    refute ApplicationHostBridge.action_scope_compatible?(
             third_party,
             organization_surface,
             mission_action
           )
  end

  test "carries explicit admitted surface identity into provider dispatch" do
    {scope, route_context} = ops_mission_context()

    params = %{
      "applicationKey" => "ops_console",
      "applicationVersion" => 1,
      "surfaceId" => "data_sources",
      "surfaceVersion" => 1,
      "actionId" => "probe-source",
      "params" => %{"selected" => true}
    }

    assert {:ok, prepared} =
             ApplicationHostBridge.prepare_action(
               scope,
               route_context,
               params,
               "bridge-surface-identity",
               now: @now
             )

    assert %ActionRequest{
             surface_id: "data_sources",
             surface_version: 1,
             params: %{"selected" => true}
           } = prepared.dispatch_request

    assert prepared.request_document["surfaceId"] == "data_sources"
    assert prepared.request_document["surfaceVersion"] == 1
  end

  test "requires the exact surface identity for every action" do
    {scope, route_context} = ops_mission_context()

    params = %{
      "applicationKey" => "ops_console",
      "applicationVersion" => 1,
      "actionId" => "probe-source",
      "params" => %{"selected" => true}
    }

    assert {:error, :invalid_application_request} =
             ApplicationHostBridge.prepare_action(
               scope,
               route_context,
               params,
               "bridge-legacy-surface",
               now: @now
             )
  end

  test "returns stable host ids for every application scope" do
    assert ApplicationHostBridge.host_dom_id(:mission) == "mission-application-host"
    assert ApplicationHostBridge.host_dom_id(:spacecraft) == "spacecraft-application-host"
    assert ApplicationHostBridge.host_dom_id(:user) == "user-application-host"
  end

  defp ops_mission_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    {scope,
     %{
       host_context: HostContext.mission(mission.mission_id),
       mission: mission,
       spacecraft: nil
     }}
  end
end
