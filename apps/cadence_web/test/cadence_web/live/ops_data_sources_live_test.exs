defmodule CadenceWeb.OpsDataSourcesLiveTest do
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

  test "data sources forward only the bounded source subject" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?data_source_id=source-1&stale=ignored"
      )

    assert_surface(view, "ops-data-sources-component", "data_sources", mission, %{
      "data_source_id" => "source-1"
    })
  end

  test "data sources remain authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/data-sources")
  end

  test "the source provider rejects a cross-mission subject" do
    request = %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "data_sources",
      surface_version: 1,
      query_id: "cadence.ops.data_sources",
      query_version: 1,
      params: %{"mission_id" => "mission-2", "data_source_id" => "source-1"}
    }

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %Scope{organization_id: "org-1"},
               HostContext.mission("mission-1"),
               request
             )
  end

  defp signed_in do
    {conn, _user, _organization, mission} = signed_in_user_org_and_mission()
    {conn, mission}
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), user, organization, mission}
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "surface_id" => surface_id,
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params
           }
  end
end
