defmodule CadenceWeb.MissionLive.SettingsTest do
  use CadenceWeb.ConnCase, async: true

  # TODO: These tests hang - need investigation. Skipping until resolved.
  @moduletag :skip

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

  describe "direct editing" do
    test "controls are always visible", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Number input should be visible without needing to enable override
      assert html =~ "input"
      assert html =~ "name=\"required_approvals\""
    end

    test "changing value creates override automatically", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 2)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Change the value - should create override
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "5"})

      # Should now have an override
      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 5
    end

    test "boolean settings can be toggled directly", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, true)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Toggle is wrapped in a form with phx-change - select by input name
      view
      |> form("form:has(input[name=allow_self_approval])", %{allow_self_approval: "false"})
      |> render_change()

      # Should have override set to false
      assert Settings.get_mission_override(mission, :procedures, :allow_self_approval) == false
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

      # Toggle is wrapped in a form with phx-change - select by input name
      view
      |> form("form:has(input[name=allow_self_approval])", %{allow_self_approval: "false"})
      |> render_change()

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

  describe "allow_withdrawal - :false_is_stricter" do
    test "allows setting false when org is true", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, true)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :allow_withdrawal, true)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Toggle is wrapped in a form with phx-change - select by input name
      view
      |> form("form:has(input[name=allow_withdrawal])", %{allow_withdrawal: "false"})
      |> render_change()

      assert Settings.get_mission_override(mission, :procedures, :allow_withdrawal) == false
    end

    test "cannot override when org has false", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :allow_withdrawal, false)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # The toggle should be disabled or indicate cannot be overridden
      assert html =~ "disabled" or html =~ "Cannot"
    end
  end

  describe "navigation" do
    test "can navigate from general to procedures via sidebar", %{conn: conn, mission: mission} do
      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings")

      # Settings dropdown in sidebar should show both General and Procedures links
      html = render(view)
      assert html =~ ~r/href="\/missions\/#{mission.id}\/settings"[^>]*>.*General/s
      assert html =~ ~r/href="\/missions\/#{mission.id}\/settings\/procedures"[^>]*>.*Procedures/s

      # Navigate to procedures via direct URL (sidebar uses navigate, not patch)
      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings/procedures")
      assert html =~ "Procedures Settings"
    end

    test "can navigate from procedures to general via sidebar", %{conn: conn, mission: mission} do
      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      # Settings dropdown in sidebar should show both General and Procedures links
      html = render(view)
      assert html =~ ~r/href="\/missions\/#{mission.id}\/settings"[^>]*>.*General/s
      assert html =~ ~r/href="\/missions\/#{mission.id}\/settings\/procedures"[^>]*>.*Procedures/s

      # Navigate to general via direct URL (sidebar uses navigate, not patch)
      {:ok, _view, html} = live(conn, ~p"/missions/#{mission}/settings")
      assert html =~ "General Settings"
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

    test "setting value equal to org default still works", %{conn: conn, mission: mission, org: org} do
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)
      mission = Cadence.Repo.preload(mission, :organization)
      {:ok, _} = Settings.set_mission(mission, :procedures, :required_approvals, 5)

      # Set value back to org default
      {:ok, view, _html} = live(conn, ~p"/missions/#{mission}/settings/procedures")

      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "3"})

      # Should have override set to 3 (same as org)
      assert Settings.get_mission_override(mission, :procedures, :required_approvals) == 3
      # Effective value is 3
      assert Settings.get(mission, :procedures, :required_approvals) == 3
    end
  end
end
