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
    assert_directory(planning, mission, %{})

    {:ok, paged, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning?page=2&state=failed")

    assert_directory(paged, mission, %{
      "page" => "2",
      "state" => "failed"
    })

    {:ok, new_run, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert_workflow(new_run, "planning.fleet-start", mission, %{})

    {:ok, policy, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert_workflow(policy, "planning.fleet-policy", mission, %{})

    {:ok, templates, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert_workflow(templates, "planning.requirement-templates", mission, %{})
    page = LiveVue.Test.get_vue(templates, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["status"] == "ready"
    assert page["data"]["model"]["can_manage"]
    assert page["data"]["model"]["templates"]["entries"] == []

    {:ok, run, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/runs/run-1")

    assert_workflow(run, "planning.fleet-run", mission, %{
      "fleet_planning_run_id" => "run-1"
    })

    {:ok, evidence, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning/runs/run-1?requirements_page=2&decisions_page=3&resources_page=2&automation_page=4&commitments_page=2"
      )

    assert_workflow(evidence, "planning.fleet-run", mission, %{
      "fleet_planning_run_id" => "run-1",
      "requirements_page" => "2",
      "decisions_page" => "3",
      "resources_page" => "2",
      "automation_page" => "4",
      "commitments_page" => "2"
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
    assert {:ok, %{subject_param: nil, query_params: ["page", "state"]}} =
             OpsConsole.surface_query_contract("fleet_planning")

    assert {:ok,
            %{
              subject_param: nil,
              query_params: [
                "requirements_page",
                "decisions_page",
                "resources_page",
                "automation_page",
                "commitments_page"
              ]
            }} =
             OpsConsole.surface_query_contract("fleet_planning_run")
  end

  defp assert_directory(view, mission, query) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "ops_module",
      "contribution" => "planning.fleet-directory",
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query
    })
  end

  defp assert_workflow(view, contribution, mission, query) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "ops_module",
      "contribution" => contribution,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query
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
