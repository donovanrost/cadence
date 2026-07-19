defmodule CadenceWeb.SpacecraftNewLiveTest do
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
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders the form" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert has_element?(view, "#spacecraft-new-page")
      assert has_element?(view, "#spacecraft-form")
      assert html =~ "New Spacecraft"
      assert html =~ "Display Name"
      assert html =~ "SCID"
      assert html =~ "Spacecraft Profile"
      assert html =~ "Create Spacecraft"

      page = render(element(view, "#spacecraft-new-page"))
      refute page =~ "Transport"
      refute page =~ "Routing"
      refute page =~ "Contact"
      refute page =~ "Provider"
      refute page =~ "Path"
      refute page =~ "Link"
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/new")
    end

    test "missing mission redirects to /missions" do
      {conn, _org, _mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/missing/spacecraft/new")
    end
  end

  describe "save" do
    test "creating with valid data persists and redirects to show page" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#spacecraft-form", spacecraft: %{display_name: "Orbital-1"})
               |> render_submit()

      assert target =~ "/missions/#{mission.mission_id}/spacecraft/"

      [persisted] =
        Cadence.SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id)

      assert persisted.display_name == "Orbital-1"
      assert target =~ persisted.spacecraft_id
    end

    test "creating with SCID persists spacecraft identity and creates a managed source endpoint" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert {:error, {:live_redirect, %{to: _target}}} =
               view
               |> form("#spacecraft-form", spacecraft: %{display_name: "Orbital-42", scid: "42"})
               |> render_submit()

      [persisted] =
        Cadence.SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id)

      assert persisted.scid == 42

      assert [endpoint] =
               Cadence.list_source_endpoints(org.organization_id, mission.mission_id,
                 spacecraft_id: persisted.spacecraft_id
               )

      assert endpoint.scid == 42
      assert endpoint.metadata["managed_by"] == "spacecraft"
    end

    test "blank display_name shows a flash error and stays on page" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      html =
        view
        |> form("#spacecraft-form", spacecraft: %{display_name: "   "})
        |> render_submit()

      assert html =~ "Display name is required."
    end
  end
end
