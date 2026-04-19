defmodule CadenceWeb.MissionNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  describe "render" do
    test "renders the empty form" do
      {conn, _org} = signed_in_conn()

      {:ok, _view, html} = live(conn, ~p"/missions/new")

      assert html =~ "New Mission"
      assert html =~ "Display Name"
      assert html =~ "Slug"
    end
  end

  describe "auto slug" do
    test "derives slug from display_name on validate when slug is empty" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      html =
        view
        |> form("#mission-form", mission: %{display_name: "Alpha Mission", slug: ""})
        |> render_change()

      assert html =~ ~s(value="alpha-mission")
    end

    test "preserves user-entered slug even when display_name changes" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      view
      |> form("#mission-form", mission: %{display_name: "Foo", slug: "custom-slug"})
      |> render_change()

      html =
        view
        |> form("#mission-form", mission: %{display_name: "Bar", slug: "custom-slug"})
        |> render_change()

      assert html =~ ~s(value="custom-slug")
    end
  end

  describe "submit" do
    test "creates the mission and navigates to its show page" do
      {conn, org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      view
      |> form("#mission-form", mission: %{display_name: "Alpha", slug: "alpha"})
      |> render_submit()

      {redirect_path, _flash} = assert_redirect(view)
      assert redirect_path =~ ~r|^/missions/mission_|

      assert [mission] = Cadence.list_missions(org.organization_id)
      assert mission.slug == "alpha"
      assert mission.display_name == "Alpha"
    end

    test "flashes an error when display_name is blank" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      html =
        view
        |> form("#mission-form", mission: %{display_name: "", slug: "alpha"})
        |> render_submit()

      assert html =~ "required"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions/new")
    end

    test "user without membership redirects to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} = live(conn, ~p"/missions/new")
    end
  end
end
