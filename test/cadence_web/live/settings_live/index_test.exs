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

    test "shows general tab as active on index", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")

      # Check that General tab has active styling
      assert html =~ "bg-primary"
      assert html =~ "General settings coming soon"
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

  describe "saving settings" do
    test "updates integer setting", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change the required_approvals setting
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "required_approvals", value: "5"})

      # Verify the setting was updated
      assert Settings.get_org(org, :procedures, :required_approvals) == 5

      # Verify flash message
      assert render(view) =~ "Setting updated"
    end

    test "updates boolean setting to false", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change allow_self_approval to false
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "allow_self_approval", value: "false"})

      assert Settings.get_org(org, :procedures, :allow_self_approval) == false
    end

    test "updates boolean setting to true", %{conn: conn, org: org} do
      # First set it to false
      {:ok, _} = Settings.set_org(org, :procedures, :allow_self_approval, false)

      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change it back to true
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "allow_self_approval", value: "true"})

      assert Settings.get_org(org, :procedures, :allow_self_approval) == true
    end

    test "shows error for invalid integer value", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Try to set value outside valid range (required_approvals is 1-10)
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "required_approvals", value: "100"})

      html = render(view)
      assert html =~ "Invalid value"

      # Value should not have changed
      assert Settings.get_org(org, :procedures, :required_approvals) == 1
    end

    test "shows error for value below minimum", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Try to set value below minimum (required_approvals minimum is 1)
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "required_approvals", value: "0"})

      html = render(view)
      assert html =~ "Invalid value"

      # Value should not have changed
      assert Settings.get_org(org, :procedures, :required_approvals) == 1
    end
  end

  describe "navigation" do
    test "can navigate from general to procedures tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      # Click procedures tab
      view
      |> element("a", "Procedures")
      |> render_click()

      assert_patched(view, ~p"/settings/procedures")
    end

    test "can navigate from procedures to general tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Click general tab
      view
      |> element("a", "General")
      |> render_click()

      assert_patched(view, ~p"/settings")
    end
  end

  describe "settings persistence" do
    test "settings persist across page reloads", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/settings/procedures")

      # Change a setting
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "required_approvals", value: "7"})

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
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "required_approvals", value: "3"})

      # Change allow_self_approval
      view
      |> element("form[phx-change=\"save_setting\"]")
      |> render_change(%{key: "allow_self_approval", value: "false"})

      # Verify both settings
      assert Settings.get_org(org, :procedures, :required_approvals) == 3
      assert Settings.get_org(org, :procedures, :allow_self_approval) == false
    end
  end
end
