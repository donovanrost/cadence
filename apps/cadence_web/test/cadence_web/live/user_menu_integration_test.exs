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

      {:ok, view, _html} = live(conn, ~p"/notifications")

      user_menu = LiveVue.Test.get_vue(view, id: "user-menu")
      notifications_bell = LiveVue.Test.get_vue(view, id: "notifications-bell")

      assert user_menu.component == "UserMenu"
      assert user_menu.props["presentation"]["trigger"]["label"]["text"] == "Shell User"

      assert user_menu.props["presentation"]["menu"]["sign_out"]["attrs"] == %{
               "action" => "/session",
               "method" => "post"
             }

      assert notifications_bell.component == "NotificationsBell"
    end

    test "renders trigger and organization block in sidebar (/)" do
      user = TestFixtures.persist_user!(display_name: "Org User")
      org = TestFixtures.persist_org!(display_name: "Integration Co")
      _ = TestFixtures.grant_membership!(user, org)
      conn = TestFixtures.member_conn(user)

      {:ok, view, _html} = live(conn, ~p"/")

      mobile = LiveVue.Test.get_vue(view, id: "user-menu-mobile")
      desktop = LiveVue.Test.get_vue(view, id: "user-menu-desktop")

      assert mobile.component == "UserMenu"
      assert desktop.component == "UserMenu"
      assert desktop.props["presentation"]["trigger"]["label"]["text"] == "Org User"

      assert desktop.props["presentation"]["menu"]["organization"]["label"]["text"] ==
               "ORGANIZATION"

      assert desktop.props["presentation"]["menu"]["organization"]["current"]["text"] ==
               "Integration Co"
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

      assert {:ok, persisted} = Cadence.Missions.persist_mission(mission)

      conn = TestFixtures.member_conn(user)

      {:ok, view, _html} = live(conn, ~p"/missions/#{persisted.mission_id}")

      mobile = LiveVue.Test.get_vue(view, id: "user-menu-mobile")
      desktop = LiveVue.Test.get_vue(view, id: "user-menu-desktop")

      assert mobile.component == "UserMenu"
      assert desktop.component == "UserMenu"
      assert desktop.props["presentation"]["trigger"]["label"]["text"] == "Mission User"

      assert desktop.props["presentation"]["menu"]["organization"]["label"]["text"] ==
               "ORGANIZATION"

      assert desktop.props["presentation"]["menu"]["organization"]["current"]["text"] ==
               "Mission Org"
    end
  end
end
