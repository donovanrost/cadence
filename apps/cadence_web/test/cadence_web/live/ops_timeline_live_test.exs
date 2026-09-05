defmodule CadenceWeb.OpsTimelineLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated mission members mount the descriptor-only timeline" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/timeline?event_id=event-1&source_dashboard_id=dashboard-1"
      )

    assert_surface(view, "ops-timeline-page-component", "timeline", mission, %{})
    assert has_element?(view, "#ops-context-rail-component")
    refute has_element?(view, "#ops-timeline-page")
  end

  test "timeline query provider rejects forged and unsupported context" do
    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %Scope{organization_id: "org-1"},
               HostContext.mission("mission-1"),
               request("timeline", %{"unknown" => "value"})
             )

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %Scope{organization_id: "org-1"},
               HostContext.mission("mission-1"),
               request("timeline", %{"mission_id" => "mission-2"})
             )
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp request(surface_id, params) do
    %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: "cadence.ops.#{surface_id}",
      query_version: 1,
      params: params
    }
  end
end
