defmodule CadenceWeb.OpsContactRecordLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "contact records forward the canonical contact subject" do
    {conn, mission} = signed_in()
    contact_id = "realized-contact-1"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts/records/#{contact_id}")

    assert_surface(view, "ops-contact-record-component", "contact_record", mission, %{
      "contact_id" => contact_id
    })
  end

  test "contact records remain authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               build_conn(),
               ~p"/missions/#{mission.mission_id}/ops/contacts/records/contact-1"
             )
  end

  test "record history and section pages preserve path-owned contact identity" do
    {conn, mission} = signed_in()

    params = %{
      "contact_id" => "query-cannot-substitute",
      "revision" => "4",
      "before_revision" => "3",
      "scheduled_paths_page" => "2",
      "realized_paths_page" => "3",
      "sources_page" => "4",
      "intents_page" => "5"
    }

    {:ok, view, _} =
      live(
        conn,
        "/missions/#{mission.mission_id}/ops/contacts/records/contact-one?" <>
          URI.encode_query(params)
      )

    assert_surface(
      view,
      "ops-contact-record-component",
      "contact_record",
      mission,
      Map.put(params, "contact_id", "contact-one")
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

  defp assert_surface(view, _id, _surface_id, mission, query_params) do
    HostTransportTestSupport.assert_context(view, %{
      "kind" => "ops_module",
      "contribution" => "planning.contact-record",
      "application_key" => nil,
      "surface_id" => nil,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end
end
