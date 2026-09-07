defmodule CadenceWeb.OpsFleetPlanningLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{ActionRequest, HostContext, OpsConsole}
  alias Cadence.Applications.OpsConsole.ActionProvider
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated mission operators can navigate the fleet planning descriptor surfaces" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)
    conn = TestFixtures.member_conn(user)

    {:ok, planning, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/planning")
    assert_surface(planning, "ops-fleet-planning-component", "fleet_planning", mission, %{})

    {:ok, new_run, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert_surface(
      new_run,
      "ops-fleet-planning-new-component",
      "fleet_planning_new",
      mission,
      %{}
    )

    {:ok, policy, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert_surface(
      policy,
      "ops-fleet-planning-policy-component",
      "fleet_planning_policy",
      mission,
      %{}
    )

    {:ok, templates, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert_surface(
      templates,
      "ops-contact-requirement-template-component",
      "contact_requirement_template",
      mission,
      %{}
    )

    {:ok, run, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/runs/run-1")

    assert_surface(run, "ops-fleet-planning-run-component", "fleet_planning_run", mission, %{
      "fleet_planning_run_id" => "run-1"
    })
  end

  test "fleet planning action provider remains fail-closed and mission-scoped" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "refresh-planning",
      params: %{}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(service_scope(), HostContext.mission("mission-1"), request)

    cross_mission = %{request | params: %{"mission_id" => "mission-2"}}

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(
               service_scope(),
               HostContext.mission("mission-1"),
               cross_mission
             )
  end

  test "fleet planning query descriptors preserve subject and query contracts" do
    assert {:ok, %{subject_param: nil, query_params: []}} =
             OpsConsole.surface_query_contract("fleet_planning")

    assert {:ok, %{subject_param: nil, query_params: []}} =
             OpsConsole.surface_query_contract("fleet_planning_run")
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "ops_console",
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params,
      "surface_id" => surface_id
    })
  end

  defp service_scope do
    identity = %ServiceIdentity{
      service_identity_id: "service-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      display_name: "Fleet planning test service",
      lifecycle_state: :active
    }

    %Scope{
      actor_kind: :service,
      organization_id: "org-1",
      mission_id: "mission-1",
      service_identity: identity,
      capabilities: MapSet.new()
    }
  end
end
