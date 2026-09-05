defmodule CadenceWeb.OpsContactRequirementsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "Requirements list mounts the authenticated federated surface" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    assert_surface(
      view,
      "ops-contact-requirements-component",
      "contact_requirement_list",
      mission,
      %{}
    )
  end

  test "new Requirement mounts with no client-owned DTO" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/new")

    assert_surface(
      view,
      "ops-contact-requirement-new-component",
      "contact_requirement_new",
      mission,
      %{}
    )
  end

  test "missing Requirement and Plan subjects preserve server redirects" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    requirements_path = "/missions/#{mission.mission_id}/ops/requirements"

    assert {:error, {:live_redirect, %{to: ^requirements_path}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/missing")

    assert {:error, {:live_redirect, %{to: ^requirements_path}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/plans/missing")
  end

  test "Requirements routes remain authentication scoped" do
    {_conn, _user, _org, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/requirements")
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

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "contact-requirements")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
