defmodule CadenceWeb.SettingsLive.IndexTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Cadence.AccountsFixtures
  import Cadence.OrganizationsFixtures

  alias Cadence.Settings

  setup %{conn: conn} do
    # Create org, user is automatically associated via user_fixture
    org = organization_fixture()
    user = user_fixture(organization: org)

    conn = log_in_user(conn, user)

    %{conn: conn, user: user, org: org}
  end

  describe "GET /settings" do
    test "renders general settings tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      assert has_element?(view, "h1", "General Settings")
      assert has_element?(view, ~s(a[href="/settings"]))
      assert has_element?(view, ~s(a[href="/settings/procedures"]))
    end

    test "shows general tab as active on index", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      # Check that Organization info is shown
      assert has_element?(view, "dd", org.name)
      assert has_element?(view, "dd", org.slug)
    end
  end

  describe "GET /settings/procedures" do
    test "renders procedures settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      assert has_element?(view, "h1", "Procedures Settings")
      assert has_element?(view, "div", "Required Approvals")
      assert has_element?(view, "div", "Allow Self-Approval")
      assert has_element?(view, "div", "Allow Withdrawal")
    end

    test "displays default setting values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Default required_approvals is 1
      assert has_element?(view, ~s(input[name="required_approvals"][value="1"]))
    end

    test "displays current setting values when set", %{conn: conn, org: org} do
      # Set a non-default value
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)

      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      assert has_element?(view, ~s(input[name="required_approvals"][value="3"]))
    end
  end

  describe "saving integer settings" do
    test "updates integer setting via input change", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change the required_approvals setting via the number input
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "5"})

      # Verify the setting was updated
      assert Settings.get_org(org, :procedures, :required_approvals) == 5

      # Verify flash message
      assert has_element?(view, ~s([role="alert"]), "Setting updated")
    end

    test "updates integer setting via increment button", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Click increment button
      view
      |> element(~S(button[phx-click="increment_setting"][phx-value-name="required_approvals"]))
      |> render_click()

      # Default is 1, should now be 2
      assert Settings.get_org(org, :procedures, :required_approvals) == 2
    end

    test "updates integer setting via decrement button", %{conn: conn, org: org} do
      # First set to 5
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 5)

      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Click decrement button
      view
      |> element(~S(button[phx-click="decrement_setting"][phx-value-name="required_approvals"]))
      |> render_click()

      assert Settings.get_org(org, :procedures, :required_approvals) == 4
    end
  end

  describe "saving boolean settings" do
    test "updates boolean setting to false", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Toggle is wrapped in a form with phx-change - select by input name
      view
      |> form("form:has(input[name=allow_self_approval])", %{allow_self_approval: "false"})
      |> render_change()

      assert Settings.get_org(org, :procedures, :allow_self_approval) == false
    end

    test "updates boolean setting to true", %{conn: conn, org: org} do
      # First set it to false
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Toggle is wrapped in a form with phx-change - select by input name
      view
      |> form("form:has(input[name=allow_self_approval])", %{allow_self_approval: "true"})
      |> render_change()

      assert Settings.get_org(org, :procedures, :allow_self_approval) == true
    end
  end

  describe "validation" do
    test "decrement button disabled at minimum", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # The decrement button should be disabled when at minimum (1)
      assert has_element?(
               view,
               ~S(button[phx-click="decrement_setting"][phx-value-name="required_approvals"][disabled])
             )
    end
  end

  describe "navigation" do
    test "can navigate from general to procedures via sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      # Settings dropdown in sidebar should show both General and Procedures links
      assert has_element?(view, ~s(a[href="/settings"]))
      assert has_element?(view, ~s(a[href="/settings/procedures"]))

      # Navigate to procedures via direct URL (sidebar uses navigate, not patch)
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")
      assert has_element?(view, "h1", "Procedures Settings")
    end

    test "can navigate from procedures to general via sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Settings dropdown in sidebar should show both General and Procedures links
      assert has_element?(view, ~s(a[href="/settings"]))
      assert has_element?(view, ~s(a[href="/settings/procedures"]))

      # Navigate to general via direct URL (sidebar uses navigate, not patch)
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert has_element?(view, "h1", "General Settings")
    end
  end

  describe "settings persistence" do
    test "settings persist across page reloads", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change a setting via input
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "7"})

      # Verify it persisted
      assert Settings.get_org(org, :procedures, :required_approvals) == 7

      # Reload the page
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Value should still be 7
      assert has_element?(view, ~s(input[name="required_approvals"][value="7"]))
    end

    test "multiple settings can be changed independently", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change required_approvals
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "3"})

      # Toggle is wrapped in a form with phx-change - select by input name
      view
      |> form("form:has(input[name=allow_self_approval])", %{allow_self_approval: "false"})
      |> render_change()

      # Verify both settings
      assert Settings.get_org(org, :procedures, :required_approvals) == 3
      assert Settings.get_org(org, :procedures, :allow_self_approval) == false
    end
  end
end
