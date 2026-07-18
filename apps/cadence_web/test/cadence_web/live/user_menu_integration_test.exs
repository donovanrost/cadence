defmodule CadenceWeb.UserMenuIntegrationTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :integration

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  describe "user_menu rendered in authenticated shells" do
    test "renders trigger in user_shell (/notifications)" do
      user = TestFixtures.persist_user!(display_name: "Shell User")
      conn = TestFixtures.member_conn(user)

      {:ok, _view, html} = live(conn, ~p"/notifications")

      # Trigger renders display_name as the header control.
      assert html =~ "Shell User"
      # The user-menu popover is present (sign-out form is part of the panel).
      assert html =~ ~s|action="/session"|
    end

    test "renders trigger and organization block in sidebar (/)" do
      user = TestFixtures.persist_user!(display_name: "Org User")
      org = TestFixtures.persist_org!(display_name: "Integration Co")
      _ = TestFixtures.grant_membership!(user, org)
      conn = TestFixtures.member_conn(user)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Org User"
      assert html =~ "ORGANIZATION"
      assert html =~ "Integration Co"
    end

    test "renders trigger and organization block in mission_sidebar (/missions/:id)" do
      user = TestFixtures.persist_user!(display_name: "Mission User")
      org = TestFixtures.persist_org!(display_name: "Mission Org")
      _ = TestFixtures.grant_membership!(user, org)

      mission =
        Mission.new(%{
          organization_id: org.organization_id,
          slug: "integration-#{System.unique_integer([:positive])}",
          display_name: "Integration Mission"
        })

      assert {:ok, persisted} = Cadence.persist_mission(mission)

      conn = TestFixtures.member_conn(user)

      {:ok, _view, html} = live(conn, ~p"/missions/#{persisted.mission_id}")

      assert html =~ "Mission User"
      assert html =~ "ORGANIZATION"
      assert html =~ "Mission Org"
    end
  end
end
