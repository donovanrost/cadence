defmodule CadenceWeb.MissionLive.SettingsTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Cadence.AccountsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures

  alias Cadence.Settings

  setup %{conn: conn} do
    org = organization_fixture()
    mission = mission_fixture(organization: org)
    user = user_fixture(organization: org)

    conn = log_in_user(conn, user)

    %{conn: conn, user: user, org: org, mission: mission}
  end

  describe "GET /missions/:id/settings" do
    test "renders general settings tab", %{conn: conn, mission: mission} do
      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings")

      assert html =~ "Mission Settings"
      assert html =~ "General"
      assert html =~ "Procedures"
    end

    test "shows mission info on general tab", %{conn: conn, mission: mission} do
      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings")

      assert html =~ mission.name
      assert html =~ mission.status
    end
  end

  describe "GET /missions/:id/settings/procedures" do
    test "shows org defaults", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      assert html =~ "Organization default"
      assert html =~ "2"
    end

    test "shows existing override", %{conn: conn, mission: mission} do
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 5)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Override value should be shown
      assert html =~ ~s(value="5")
    end

    test "shows all procedure settings", %{conn: conn, mission: mission} do
      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      assert html =~ "Required Approvals"
      assert html =~ "Allow Self-Approval"
      assert html =~ "Allow Withdrawal"
    end
  end

  describe "toggle_override" do
    test "enables override with org default value", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Click to enable override
      view
      |> element("[phx-click=\"toggle_override\"][phx-value-key=\"required_approvals\"]")
      |> render_click()

      # Should now have an override set to org value
      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 2
    end

    test "disables override and clears value", %{conn: conn, mission: mission} do
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 5)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Click to disable override
      view
      |> element("[phx-click=\"toggle_override\"][phx-value-key=\"required_approvals\"]")
      |> render_click()

      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == nil
    end

    test "can toggle boolean setting override", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, true)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Enable override
      view
      |> element("[phx-click=\"toggle_override\"][phx-value-key=\"allow_self_approval\"]")
      |> render_click()

      # Should have override set
      assert Settings.get_mission_override(mission, :procedures, :allow_self_approval) == true
    end
  end

  describe "restrictiveness validation - :higher" do
    test "prevents setting less restrictive value", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 3)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Try to set to 2 (less than org's 3) via input change
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "2"})

      html = render(view)
      assert html =~ "Must be at least 3"

      # Value should not have changed
      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 3
    end

    test "allows setting more restrictive value", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 2)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "5"})

      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 5
    end

    test "allows setting equal value", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 5)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Set to equal the org value
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "3"})

      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 3
    end
  end

  describe "restrictiveness validation - :false_is_stricter" do
    test "allows setting false when org is true", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, true)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :allow_self_approval, true)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      view
      |> element("input[name=\"allow_self_approval\"][type=\"checkbox\"]")
      |> render_change(%{allow_self_approval: "false"})

      assert Settings.get_mission_override(mission, :procedures, :allow_self_approval) == false
    end

    test "cannot override when org has false", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # The toggle should be disabled or indicate cannot be overridden
      # In the HEAD implementation, override is disabled for false_is_stricter when org is false
      assert html =~ "disabled" or html =~ "Cannot"
    end
  end

  describe "restrictiveness validation - :none" do
    test "allows any value regardless of org setting", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, false)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :allow_withdrawal, false)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Should be able to set to true even when org is false
      view
      |> element("input[name=\"allow_withdrawal\"][type=\"checkbox\"]")
      |> render_change(%{allow_withdrawal: "true"})

      assert Settings.get_mission_override(mission, :procedures, :allow_withdrawal) == true
    end

    test "allows setting false when org is true", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, true)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :allow_withdrawal, true)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      view
      |> element("input[name=\"allow_withdrawal\"][type=\"checkbox\"]")
      |> render_change(%{allow_withdrawal: "false"})

      assert Settings.get_mission_override(mission, :procedures, :allow_withdrawal) == false
    end
  end

  describe "navigation" do
    test "can navigate from general to procedures tab", %{conn: conn, mission: mission} do
      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings")

      # Click procedures tab in desktop navigation (hidden lg:flex)
      view
      |> element("ul.hidden.lg\\:flex a[href=\"/missions/#{mission.id}/settings/procedures\"]")
      |> render_click()

      assert_patched(view, ~p"/missions/#{mission}/settings/procedures")
    end

    test "can navigate from procedures to general tab", %{conn: conn, mission: mission} do
      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Click general tab in desktop navigation (hidden lg:flex)
      view
      |> element("ul.hidden.lg\\:flex a[href=\"/missions/#{mission.id}/settings\"]")
      |> render_click()

      assert_patched(view, ~p"/missions/#{mission}/settings")
    end
  end

  describe "effective values" do
    test "mission uses org default when no override", %{conn: _conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 4)

      mission = Cadence.Repo.preload(mission, :organization)
      assert Settings.get(mission, :procedures, :required_approvals) == 4
    end

    test "mission uses override when set", %{conn: _conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 5)

      assert Settings.get(mission, :procedures, :required_approvals) == 5
    end

    test "clearing override reverts to org default", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 5)

      # Clear the override
      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      view
      |> element("[phx-click=\"toggle_override\"][phx-value-key=\"required_approvals\"]")
      |> render_click()

      # Should now use org default
      mission = Cadence.Repo.preload(mission, :organization)
      assert Settings.get(mission, :procedures, :required_approvals) == 3
    end
  end
end
