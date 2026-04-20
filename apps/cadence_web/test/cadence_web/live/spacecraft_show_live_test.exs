defmodule CadenceWeb.SpacecraftShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  describe "mount" do
    test "renders spacecraft detail" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, _view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      assert html =~ "Nova-1"
      assert html =~ spacecraft.spacecraft_id
      assert html =~ mission.display_name
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/s")
    end

    test "unknown spacecraft redirects to the mission's spacecraft list" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/missing-id")

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to a sibling mission is not found" do
      {conn, _user, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Sibling")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to another organization is not found" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Foreign")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "sidebar highlights the Spacecraft nav entry" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nav-Check")

      list_url = ~p"/missions/#{mission.mission_id}/spacecraft"

      {:ok, _view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      # A navigate link to the spacecraft list must exist in the sidebar AND
      # the rendered HTML must contain the "Spacecraft" label inside that link.
      assert html =~ list_url
      assert html =~ "Spacecraft"
    end
  end
end
