defmodule CadenceWeb.OpsContactRequirementsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "requirements routes expose exact compiled and historical subjects" do
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

  test "contact planning pages remain authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/requirements")

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/plans/plan-1?version=2")
  end

  test "plan review parameters reach the host with path-owned plan identity" do
    {conn, mission} = signed_in()

    params = %{
      "version" => "2",
      "versions_page" => "3",
      "approvals_page" => "4",
      "opportunities_page" => "5",
      "execution_page" => "6",
      "requirements_page" => "7",
      "issues_page" => "8",
      "contact_plan_id" => "query-cannot-replace-plan"
    }

    {:ok, view, _html} =
      live(conn, "/missions/#{mission.mission_id}/ops/plans/plan-1?" <> URI.encode_query(params))

    assert_surface(
      view,
      "ops-contact-plan-show-component",
      "contact_plan_show",
      mission,
      Map.put(params, "contact_plan_id", "plan-1")
    )
  end

  test "requirements pagination and lifecycle filters reach the scoped query" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(conn, "/missions/#{mission.mission_id}/ops/requirements?page=2&state=closed")

    assert_surface(
      view,
      "ops-contact-requirements-component",
      "contact_requirement_list",
      mission,
      %{"page" => "2", "state" => "closed"}
    )
  end

  test "detail review identity and all page parameters reach the host query",
    do: assert_review_query()

  defp assert_review_query do
    {conn, mission} = signed_in()

    params = %{
      "version" => "2",
      "planning_run_id" => "run-1",
      "versions_page" => "3",
      "runs_page" => "2",
      "searches_page" => "4",
      "opportunities_page" => "5"
    }

    {:ok, view, _html} =
      live(
        conn,
        "/missions/#{mission.mission_id}/ops/requirements/requirement-1?" <>
          URI.encode_query(params)
      )

    assert_surface(
      view,
      "ops-contact-requirement-show-component",
      "contact_requirement_show",
      mission,
      Map.put(params, "contact_requirement_id", "requirement-1")
    )
  end

  test "reservation review cursors preserve the authenticated path-owned reservation" do
    {conn, mission} = signed_in()

    params = %{
      "provider_reservation_id" => "query-substitution",
      "change_id" => "change-2",
      "before_revision" => "10",
      "before_audit" => "audit-25"
    }

    {:ok, view, _} =
      live(
        conn,
        "/missions/#{mission.mission_id}/ops/contacts/reservation-1?" <> URI.encode_query(params)
      )

    assert_surface(
      view,
      "ops-contact-detail-component",
      "contact_detail",
      mission,
      Map.put(params, "provider_reservation_id", "reservation-1")
    )

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/#{mission.mission_id}/ops/contacts/reservation-1")
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

  defp assert_surface(view, _id, "contact_detail", mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "ops_module",
      "contribution" => "planning.reservation-review",
      "application_key" => nil,
      "surface_id" => nil,
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end

  defp assert_surface(view, _id, "contact_plan_show", mission, query_params) do
    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    page = snapshot["ops_page"]
    assert page["id"] == "planning.plan-review"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["context"]["resourceId"] == query_params["contact_plan_id"]
    assert page["status"] == "unavailable"

    HostTransportTestSupport.assert_context(view, %{
      "kind" => "ops_module",
      "contribution" => "planning.plan-review",
      "application_key" => nil,
      "surface_id" => nil,
      "query_params" => query_params
    })
  end

  defp assert_surface(view, _id, surface, mission, query_params)
       when surface in ["contact_requirement_list", "contact_requirement_show"] do
    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    page = snapshot["ops_page"]
    assert page["slot"] == "ops.page"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["token"]

    if surface == "contact_requirement_list" do
      assert page["id"] == "planning.requirement-directory"

      assert page["data"]["query"] == %{
               "page" => String.to_integer(Map.get(query_params, "page", "1")),
               "state" => Map.get(query_params, "state", "all")
             }
    else
      assert page["id"] == "planning.requirement-review"
      assert page["context"]["resourceId"] == query_params["contact_requirement_id"]
      assert page["status"] == "unavailable"
    end
  end

  defp assert_surface(view, _id, "contact_requirement_new", mission, _query_params) do
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "planning.requirement-declaration"
    assert page["status"] == "ready"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["data"]["model"]["spacecraft"]["total"] == 0
    refute page["data"]["model"]["can_declare"]
  end

  defp assert_surface(view, _id, "contact_requirement_template", mission, _query_params) do
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["id"] == "planning.requirement-templates"
    assert page["status"] == "ready"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["data"]["model"]["templates"]["entries"] == []
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
