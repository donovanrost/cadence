defmodule CadenceWeb.OpsDashboardAuthoringEntryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "dashboard authoring entry mounts the federated directory and new surface" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, directory, _html} = live(conn, directory_path(mission))

    assert_surface(
      directory,
      "ops-dashboard-directory-component",
      "dashboard_directory",
      mission,
      %{}
    )

    {:ok, new_view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new?mode=import")

    assert_surface(new_view, "ops-dashboard-new-component", "dashboard_new", mission, %{})
  end

  test "new dashboard save remains a durable provider outcome" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

    render_hook(view, "save", %{
      "dashboard" => %{"name" => "Federated Dashboard", "description" => "Created by the route"}
    })

    {path, _flash} = assert_redirect(view)
    assert path =~ "/missions/#{mission.mission_id}/ops/dashboards/"

    assert [%Document{name: "Federated Dashboard", organization_id: organization_id}] =
             Cadence.Dashboards.list_documents(org.organization_id, mission.mission_id)

    assert organization_id == org.organization_id
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = LiveVue.Test.get_vue(view, id: id)
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

  defp directory_path(mission), do: ~p"/missions/#{mission.mission_id}/ops/dashboards"

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-authoring")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
