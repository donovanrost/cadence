defmodule CadenceWeb.UITest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Accounts.User
  alias Cadence.Organizations.Organization
  alias CadenceWeb.UI

  defp scope(user, organization \\ nil) do
    %Cadence.Auth.Scope{user: user, organization: organization, capabilities: MapSet.new()}
  end

  defp user_fixture(attrs \\ %{}) do
    User.new(
      Map.merge(
        %{
          email: "jane@example.com",
          display_name: "Jane Rost"
        },
        attrs
      )
    )
  end

  defp org_fixture(attrs) do
    Organization.new(
      Map.merge(
        %{
          display_name: "Acme Space",
          slug: "acme-#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
  end

  defp render_user_menu(opts \\ []) do
    [
      id: "user-menu",
      scope: scope(user_fixture()),
      memberships: [],
      platform_admin?: false
    ]
    |> Keyword.merge(opts)
    |> then(fn assigns -> render_component(&UI.user_menu/1, assigns) end)
    |> LazyHTML.from_fragment()
  end

  defp organization_block(document) do
    document
    |> LazyHTML.query("#user-menu-menu .hud-label")
    |> LazyHTML.parent_node()
  end

  describe "user_menu/1" do
    test "renders display_name as trigger text" do
      trigger =
        render_user_menu()
        |> LazyHTML.query("#user-menu > button[data-dropdown-trigger]")

      assert LazyHTML.text(trigger) =~ "Jane Rost"
    end

    test "renders identity block with name and email" do
      identity =
        render_user_menu()
        |> LazyHTML.query("#user-menu-menu > div[role='presentation']")

      assert LazyHTML.text(identity) =~ "Jane Rost"
      assert LazyHTML.text(identity) =~ "jane@example.com"
    end

    test "always renders sign-out form targeting DELETE /session" do
      document = render_user_menu()
      sign_out_form = LazyHTML.query(document, "#user-menu-menu form[action='/session']")

      assert Enum.count(sign_out_form) == 1

      assert sign_out_form
             |> LazyHTML.query("input[name='_method'][value='delete']")
             |> Enum.count() == 1

      assert sign_out_form
             |> LazyHTML.query("button[type='submit'][role='menuitem']")
             |> LazyHTML.text() =~ "Sign out"
    end

    test "omits the organization block entirely when scope.organization is nil" do
      assert render_user_menu()
             |> LazyHTML.query("#user-menu-menu .hud-label")
             |> Enum.empty?()
    end

    test "renders label-only org row for single-membership users" do
      org = org_fixture(%{display_name: "Acme Space"})
      membership_map = %{membership: %{}, organization: org}

      org_block =
        render_user_menu(scope: scope(user_fixture(), org), memberships: [membership_map])
        |> organization_block()

      assert LazyHTML.text(org_block) =~ "ORGANIZATION"
      assert LazyHTML.text(org_block) =~ "Acme Space"
      assert org_block |> LazyHTML.query("details") |> Enum.empty?()

      assert org_block
             |> LazyHTML.query("form[action='/session/organization']")
             |> Enum.empty?()
    end

    test "renders expandable switcher for multi-membership users" do
      current_org = org_fixture(%{display_name: "Acme Space"})
      other_org = org_fixture(%{display_name: "Beta Labs"})

      org_block =
        render_user_menu(
          scope: scope(user_fixture(), current_org),
          memberships: [
            %{membership: %{}, organization: current_org},
            %{membership: %{}, organization: other_org}
          ]
        )
        |> organization_block()

      assert LazyHTML.text(org_block) =~ "ORGANIZATION"
      assert LazyHTML.text(org_block) =~ "Acme Space"
      assert LazyHTML.text(org_block) =~ "Beta Labs"
      assert org_block |> LazyHTML.query("details") |> Enum.count() == 1

      switch_form = LazyHTML.query(org_block, "form[action='/session/organization']")

      assert switch_form
             |> LazyHTML.query("input[name='_method'][value='put']")
             |> Enum.count() == 1

      assert switch_form
             |> LazyHTML.query(
               ~s|input[name="organization_id"][value="#{other_org.organization_id}"]|
             )
             |> Enum.count() == 1

      assert switch_form
             |> LazyHTML.query(
               ~s|input[name="organization_id"][value="#{current_org.organization_id}"]|
             )
             |> Enum.empty?()
    end

    test "does not render the system administration link when platform_admin? is false" do
      document = render_user_menu()

      assert document
             |> LazyHTML.query("#user-menu-menu a[href='/admin']")
             |> Enum.empty?()

      assert document
             |> LazyHTML.query("#user-menu-menu a[href='/admin-mode']")
             |> Enum.empty?()
    end

    test "renders the admin-mode entry link for an eligible user" do
      document = render_user_menu(platform_admin?: true)
      admin_mode_link = LazyHTML.query(document, "#user-menu-menu a[href='/admin-mode']")

      assert LazyHTML.text(admin_mode_link) =~ "Enter admin mode"

      assert document
             |> LazyHTML.query("#user-menu-menu form[action='/admin-mode']")
             |> Enum.empty?()
    end

    test "renders administration and exit actions while admin mode is active" do
      admin_scope = %{scope(user_fixture()) | admin_mode?: true}

      document = render_user_menu(scope: admin_scope, platform_admin?: true)
      administration_link = LazyHTML.query(document, "#user-menu-menu a[href='/admin']")
      exit_form = LazyHTML.query(document, "#user-menu-menu form[action='/admin-mode']")

      assert LazyHTML.text(administration_link) =~ "System administration"
      assert LazyHTML.text(exit_form) =~ "Leave admin mode"

      assert exit_form
             |> LazyHTML.query("input[name='_method'][value='delete']")
             |> Enum.count() == 1
    end

    test "identity block wrapper is a div so it doesn't trigger menu hover" do
      identity_name =
        render_user_menu()
        |> LazyHTML.query("#user-menu-menu > div[role='presentation'] > p:first-child")

      assert LazyHTML.text(identity_name) =~ "Jane Rost"
    end

    test "organization block wrapper is a div so it doesn't trigger menu hover" do
      org = org_fixture(%{display_name: "Acme Space"})

      org_label =
        render_user_menu(
          scope: scope(user_fixture(), org),
          memberships: [%{membership: %{}, organization: org}]
        )
        |> LazyHTML.query("#user-menu-menu > div[role='presentation'] > span.hud-label")

      assert LazyHTML.text(org_label) =~ "ORGANIZATION"
    end

    test "identity block falls back to email when display_name is blank" do
      document = render_user_menu(scope: scope(user_fixture(%{display_name: ""})))

      trigger_label =
        LazyHTML.query(document, "#user-menu > button[data-dropdown-trigger] > span:first-child")

      identity_lines =
        LazyHTML.query(document, "#user-menu-menu > div[role='presentation'] > p")

      assert LazyHTML.text(trigger_label) =~ "jane@example.com"
      assert Enum.count(identity_lines) == 1
      assert LazyHTML.text(identity_lines) =~ "jane@example.com"
    end
  end
end
