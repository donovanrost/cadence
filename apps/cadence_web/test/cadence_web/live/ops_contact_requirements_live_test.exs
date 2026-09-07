defmodule CadenceWeb.OpsContactRequirementsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "requirements routes expose exact federated subjects" do
    {conn, mission} = signed_in()

    {:ok, list, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    assert_surface(
      list,
      "ops-contact-requirements-component",
      "contact_requirement_list",
      mission,
      %{}
    )

    {:ok, new_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/new")

    assert_surface(
      new_view,
      "ops-contact-requirement-new-component",
      "contact_requirement_new",
      mission,
      %{}
    )

    {:ok, show, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/requirement-1")

    assert_surface(
      show,
      "ops-contact-requirement-show-component",
      "contact_requirement_show",
      mission,
      %{
        "contact_requirement_id" => "requirement-1"
      }
    )

    {:ok, plan, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/plans/plan-1")

    assert_surface(plan, "ops-contact-plan-show-component", "contact_plan_show", mission, %{
      "contact_plan_id" => "plan-1"
    })

    {:ok, templates, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert_surface(
      templates,
      "ops-contact-requirement-template-component",
      "contact_requirement_template",
      mission,
      %{}
    )
  end

  test "requirements remain authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/requirements")
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

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "ops_console",
      "surface_id" => surface_id,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end
end
