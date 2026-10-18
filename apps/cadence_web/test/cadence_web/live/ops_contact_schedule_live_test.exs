defmodule CadenceWeb.OpsContactScheduleLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "contacts mount the mission-scoped compiled contribution" do
    {conn, mission} = signed_in()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    assert_surface(view, "ops-contact-schedule-component", "contact_schedule", mission, %{})
  end

  test "captures independent ledger pages without allowing a query to replace host authority" do
    {conn, mission} = signed_in()

    query = %{
      "scheduled_page" => "2",
      "reservations_page" => "3",
      "spacecraft_q" => "orbiter",
      "mission_id" => "foreign",
      "untrusted" => "ignored"
    }

    {:ok, view, _} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts?#{query}")

    assert_surface(
      view,
      "ops-contact-schedule-component",
      "contact_schedule",
      mission,
      Map.take(query, ~w(scheduled_page reservations_page spacecraft_q))
    )
  end

  test "contacts remain authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/contacts")
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

  defp assert_surface(view, _id, _surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "ops_module",
      "contribution" => "planning.contact-schedule",
      "application_key" => nil,
      "surface_id" => nil,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end
end
