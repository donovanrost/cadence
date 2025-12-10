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
      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Settings"
      assert html =~ "General"
      assert html =~ "Procedures"
    end

    test "shows general tab as active on index", %{conn: conn, org: org} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      # Check that Organization info is shown
      assert html =~ org.name
      assert html =~ org.slug
    end
  end

  describe "GET /settings/procedures" do
    test "renders procedures settings", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/procedures")

      assert html =~ "Required Approvals"
      assert html =~ "Allow Self-Approval"
      assert html =~ "Allow Withdrawal"
    end

    test "displays default setting values", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/procedures")

      # Default required_approvals is 1
      assert html =~ ~s(value="1")
    end

    test "displays current setting values when set", %{conn: conn, org: org} do
      # Set a non-default value
      {:ok, _} = Settings.set_org(org, :procedures, :required_approvals, 3)

      {:ok, _view, html} = live(conn, ~p"/settings/procedures")

      assert html =~ ~s(value="3")
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
      assert render(view) =~ "Setting updated"
    end

    test "updates integer setting via increment button", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Click increment button
      view
      |> element("button[phx-click=\"increment_setting\"][phx-value-name=\"required_approvals\"]")
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
      |> element("button[phx-click=\"decrement_setting\"][phx-value-name=\"required_approvals\"]")
      |> render_click()

      assert Settings.get_org(org, :procedures, :required_approvals) == 4
    end
  end

  describe "saving boolean settings" do
    test "updates boolean setting to false", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change allow_self_approval to false via toggle (select checkbox, not hidden input)
      view
      |> element("input[name=\"allow_self_approval\"][type=\"checkbox\"]")
      |> render_change(%{allow_self_approval: "false"})

      assert Settings.get_org(org, :procedures, :allow_self_approval) == false
    end

    test "updates boolean setting to true", %{conn: conn, org: org} do
      # First set it to false
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change it back to true (select checkbox, not hidden input)
      view
      |> element("input[name=\"allow_self_approval\"][type=\"checkbox\"]")
      |> render_change(%{allow_self_approval: "true"})

      assert Settings.get_org(org, :procedures, :allow_self_approval) == true
    end
  end

  describe "validation" do
    test "decrement button disabled at minimum", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/procedures")

      # The decrement button should be disabled when at minimum (1)
      assert html =~ ~s(phx-click="decrement_setting")
      assert html =~ "disabled"
    end
  end

  describe "navigation" do
    test "can navigate from general to procedures tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      # Click procedures tab in desktop navigation (hidden lg:flex)
      view
      |> element("ul.hidden.lg\\:flex a[href=\"/settings/procedures\"]")
      |> render_click()

      assert_patched(view, ~p"/settings/procedures")
    end

    test "can navigate from procedures to general tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Click general tab in desktop navigation (hidden lg:flex)
      view
      |> element("ul.hidden.lg\\:flex a[href=\"/settings\"]")
      |> render_click()

      assert_patched(view, ~p"/settings")
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
      {:ok, _view, html} = live(conn, ~p"/settings/procedures")

      # Value should still be 7
      assert html =~ ~s(value="7")
    end

    test "multiple settings can be changed independently", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change required_approvals
      view
      |> element("input[name=\"required_approvals\"]")
      |> render_change(%{required_approvals: "3"})

      # Change allow_self_approval (select checkbox, not hidden input)
      view
      |> element("input[name=\"allow_self_approval\"][type=\"checkbox\"]")
      |> render_change(%{allow_self_approval: "false"})

      # Verify both settings
      assert Settings.get_org(org, :procedures, :required_approvals) == 3
      assert Settings.get_org(org, :procedures, :allow_self_approval) == false
    end
  end
end
