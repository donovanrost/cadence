defmodule CadenceWeb.ApplicationHostBridgeTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{
    ActionDefinition,
    ActionRequest,
    ApplicationDefinition,
    ApplicationInstallations,
    HostContext,
    JSONBoundary,
    Spacecraft,
    SurfaceDefinition
  }

  alias Cadence.Auth.Scope
  alias CadenceWeb.{ApplicationActionIdempotency, ApplicationHostBridge, TestFixtures}

  @now "2026-09-03T12:00:00Z"

  test "derived expression admission is bounded to the exact save contract and canonical replay input" do
    alias CadenceWeb.ApplicationActionInput

    input = %{
      "point_id" => "DERIVED.power",
      "point_name" => "Power",
      "expression" => String.duplicate("x", 8192),
      "expected_version" => 0,
      "expected_definition_id" => nil
    }

    request = %{
      "applicationKey" => "derived_telemetry",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "actionId" => "save_definition",
      "input" => input
    }

    assert {:ok, ^request} = ApplicationActionInput.safe(request)
    assert {:ok, _} = ApplicationActionInput.safe(Map.put(request, "params", input))

    canonical =
      request
      |> Map.drop(["actionId", "input"])
      |> Map.merge(%{
        "operation" => "save_definition",
        "operationVersion" => 1,
        "params" => input
      })

    # Generic idempotency admission validates JSON bounds, not domain-required fields.
    assert {:ok, _} =
             ApplicationActionIdempotency.request_digest(
               Map.put(canonical, "params", %{"value" => "bounded"})
             )

    assert {:ok, digest} = ApplicationActionIdempotency.request_digest(canonical)
    assert is_binary(digest)

    for {key, value} <- [
          {"applicationKey", "other"},
          {"applicationVersion", 2},
          {"surfaceId", "other"},
          {"surfaceVersion", 2},
          {"actionId", "other"},
          {"actionVersion", 2},
          {"version", 2}
        ] do
      assert {:error, :application_surface_bounds_exceeded} =
               ApplicationActionInput.safe(Map.put(request, key, value))
    end

    for bad_input <- [
          Map.put(input, "expression", String.duplicate("x", 8193)),
          Map.put(input, "point_name", String.duplicate("x", 241)),
          Map.put(input, "extra", %{}),
          Map.put(input, "expression", <<255>>)
        ] do
      assert {:error, :application_surface_bounds_exceeded} =
               ApplicationActionInput.safe(Map.put(request, "input", bad_input))
    end

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationActionInput.safe(
               Map.put(request, "params", Map.put(input, "expression", "different"))
             )

    assert {:error, :invalid_application_request} =
             ApplicationActionIdempotency.request_digest(
               Map.put(canonical, "operationVersion", 2)
             )
  end

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

  test "rejects mismatched action scopes except for bounded Mission Catalog organization actions" do
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

    assert ApplicationHostBridge.action_scope_compatible?(
             %ApplicationDefinition{third_party | application_key: "mission_catalog"},
             organization_surface,
             %ActionDefinition{mission_action | action_id: "save"}
           )
  end

  test "admits only validate and save mission actions on the Spacecraft edit surface" do
    definition = Spacecraft.definition()
    edit_surface = Enum.find(definition.surfaces, &(&1.surface_id == "edit"))

    assert %SurfaceDefinition{surface_id: "edit", scope: :spacecraft} = edit_surface

    for action_id <- ["validate", "save"] do
      assert {:ok, %ActionDefinition{scope: :mission} = action} =
               ApplicationDefinition.fetch_action(definition, action_id)

      assert ApplicationHostBridge.action_scope_compatible?(
               definition,
               edit_surface,
               action
             )
    end
  end

  test "rejects a mission action on a different Spacecraft surface" do
    definition = Spacecraft.definition()
    show_surface = Enum.find(definition.surfaces, &(&1.surface_id == "show"))
    {:ok, validate_action} = ApplicationDefinition.fetch_action(definition, "validate")

    assert %SurfaceDefinition{surface_id: "show", scope: :spacecraft} = show_surface
    assert validate_action.scope == :mission

    refute ApplicationHostBridge.action_scope_compatible?(
             definition,
             show_surface,
             validate_action
           )
  end

  test "carries explicit admitted surface identity into provider dispatch" do
    {scope, route_context} = installed_telemetry_context()

    params = %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "packet_bindings",
      "surfaceVersion" => 1,
      "actionId" => "save_packet_bindings",
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
             surface_id: "packet_bindings",
             surface_version: 1,
             params: %{"selected" => true}
           } = prepared.dispatch_request

    assert prepared.request_document["surfaceId"] == "packet_bindings"
    assert prepared.request_document["surfaceVersion"] == 1
  end

  test "requires the exact surface identity for every action" do
    {scope, route_context} = installed_telemetry_context()

    params = %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "actionId" => "save_packet_bindings",
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

  test "host admission and idempotency preserve the bounded opaque reserve token" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    scope =
      Scope.new(%{
        user: user,
        organization: organization,
        organization_id: organization.organization_id,
        organization_membership: membership
      })

    route = %{
      host_context: HostContext.mission(mission.mission_id),
      mission: mission,
      spacecraft: nil
    }

    token = String.duplicate("opaque", 400)

    params = %{
      "applicationKey" => "ops_console",
      "applicationVersion" => 1,
      "surfaceId" => "contact_schedule",
      "surfaceVersion" => 1,
      "actionId" => "reserve",
      "input" => %{"token" => token}
    }

    assert {:error, :string} = JSONBoundary.safe(params)

    assert {:ok, prepared} =
             ApplicationHostBridge.prepare_action(scope, route, params, "opaque-reserve-test",
               now: @now
             )

    assert prepared.dispatch_request.params == %{"token" => token}
    assert {:ok, _} = ApplicationActionIdempotency.request_digest(prepared.request_document)
    assert {:error, _} = ApplicationHostBridge.execute_action(scope, route, prepared, now: @now)

    assert {:error, _} =
             ApplicationHostBridge.prepare_action(
               %{scope | organization_membership: nil},
               route,
               params,
               "revoked-test",
               now: @now
             )
  end

  test "returns stable host ids for every application scope" do
    assert ApplicationHostBridge.host_dom_id(:mission) == "mission-application-host"
    assert ApplicationHostBridge.host_dom_id(:spacecraft) == "spacecraft-application-host"
    assert ApplicationHostBridge.host_dom_id(:organization) == "organization-application-host"
    assert ApplicationHostBridge.host_dom_id(:user) == "user-application-host"
    assert ApplicationHostBridge.host_dom_id(:admin) == "admin-application-host"
  end

  test "returns deep trusted organization forms through the complete host envelope" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()

    membership =
      TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    route_context = %{
      host_context: HostContext.organization(organization.organization_id),
      mission: nil,
      spacecraft: nil
    }

    params = %{
      "applicationKey" => "organization_admin",
      "applicationVersion" => 1,
      "surfaceId" => "provider_account_new",
      "surfaceVersion" => 1,
      "queryId" => "cadence.organization.provider_accounts.new",
      "queryVersion" => 1,
      "params" => %{}
    }

    assert {:ok, %{"trusted_surface" => %{"form" => form}}} =
             ApplicationHostBridge.query(scope, route_context, params, now: @now)

    assert form["id"] == "provider-account-form"
  end

  defp installed_telemetry_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "telemetry_decom")

    {scope,
     %{
       host_context: host_context,
       mission: mission,
       spacecraft: spacecraft
     }}
  end
end
