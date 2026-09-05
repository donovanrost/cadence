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
    |> LiveVue.Test.get_vue(id: "user-menu")
  end

  defp render_notifications_bell(opts \\ []) do
    [id: "notifications-bell", count: 0, notifications: []]
    |> Keyword.merge(opts)
    |> then(fn assigns -> render_component(&UI.notifications_bell/1, assigns) end)
    |> LiveVue.Test.get_vue(id: "notifications-bell")
  end

  defp menu(vue), do: vue.props["presentation"]["menu"]

  defp hidden_fields(form) do
    Map.new(form["hidden_fields"], fn %{"attrs" => attrs} -> {attrs["name"], attrs} end)
  end

  describe "notifications_bell/1" do
    test "emits one JSON-safe LiveVue host with the empty-state contract" do
      vue = render_notifications_bell()
      presentation = vue.props["presentation"]

      assert vue.component == "NotificationsBell"
      assert vue.class == "contents"
      refute vue.ssr
      assert presentation == Jason.decode!(Jason.encode!(presentation))
      assert presentation["root"]["class"] == "dropdown dropdown-end"

      assert presentation["trigger"]["attrs"] == %{
               "aria-controls" => "notifications-bell-menu",
               "aria-expanded" => "false",
               "aria-haspopup" => "menu",
               "aria-label" => "Notifications",
               "data-dropdown-trigger" => "",
               "type" => "button"
             }

      assert presentation["trigger"]["badge"] == nil
      assert presentation["menu"]["empty_state"]["label"] == "No notifications"
      assert presentation["menu"]["notifications"] == []
      assert presentation["menu"]["title"]["unread_label"] == nil
    end

    test "preserves count truncation, unread dot, body, and Phoenix navigation attrs" do
      unread = %{title: "Invitation ready", body: "As Operator", read_at: nil}
      read = %{title: "Access granted", body: nil, read_at: ~U[2026-08-24 12:00:00Z]}

      vue = render_notifications_bell(count: 14, notifications: [unread, read])
      presentation = vue.props["presentation"]
      [unread_prop, read_prop] = presentation["menu"]["notifications"]

      assert presentation["trigger"]["badge"]["text"] == "9+"
      assert presentation["menu"]["title"]["unread_label"] == "(14 unread)"
      assert presentation["menu"]["empty_state"] == nil
      assert unread_prop["dot_class"] =~ "rounded-full bg-primary"
      assert unread_prop["action"] == "mark_read"
      assert unread_prop["title"]["text"] == "Invitation ready"
      assert unread_prop["body"]["text"] == "As Operator"
      assert read_prop["dot_class"] == "mt-1.5 w-1.5 h-1.5 flex-shrink-0"
      assert read_prop["action"] == nil
      assert read_prop["body"] == nil

      assert unread_prop["link"]["attrs"] == %{
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push",
               "href" => "/notifications"
             }

      assert presentation["menu"]["footer"]["attrs"] == unread_prop["link"]["attrs"]
      assert presentation == Jason.decode!(Jason.encode!(presentation))
    end
  end

  describe "user_menu/1" do
    test "renders display_name as trigger text" do
      trigger = render_user_menu().props["presentation"]["trigger"]

      assert trigger["label"]["text"] == "Jane Rost"
      assert trigger["attrs"]["data-dropdown-trigger"] == ""
      assert trigger["attrs"]["aria-expanded"] == "false"
    end

    test "renders identity block with name and email" do
      identity = render_user_menu() |> menu() |> Map.fetch!("identity")

      assert identity["label"]["text"] == "Jane Rost"
      assert identity["email"]["text"] == "jane@example.com"
    end

    test "always renders sign-out form targeting DELETE /session" do
      sign_out = render_user_menu() |> menu() |> Map.fetch!("sign_out")
      fields = hidden_fields(sign_out)

      assert sign_out["attrs"] == %{"action" => "/session", "method" => "post"}
      assert fields["_method"]["type"] == "hidden"
      assert fields["_method"]["value"] == "delete"
      assert fields["_csrf_token"]["hidden"] == ""
      assert is_binary(fields["_csrf_token"]["value"])
      assert fields["_csrf_token"]["value"] != ""
      assert sign_out["button"]["attrs"] == %{"role" => "menuitem", "type" => "submit"}
      assert sign_out["button"]["label"] == "Sign out"
    end

    test "omits the organization block entirely when scope.organization is nil" do
      assert render_user_menu() |> menu() |> Map.fetch!("organization") == nil
    end

    test "renders label-only org row for single-membership users" do
      org = org_fixture(%{display_name: "Acme Space"})
      membership_map = %{membership: %{}, organization: org}

      organization =
        render_user_menu(scope: scope(user_fixture(), org), memberships: [membership_map])
        |> menu()
        |> Map.fetch!("organization")

      assert organization["label"]["text"] == "ORGANIZATION"
      assert organization["current"]["text"] == "Acme Space"
      assert organization["switcher"] == nil
    end

    test "renders expandable switcher for multi-membership users" do
      current_org = org_fixture(%{display_name: "Acme Space"})
      other_org = org_fixture(%{display_name: "Beta Labs"})

      organization =
        render_user_menu(
          scope: scope(user_fixture(), current_org),
          memberships: [
            %{membership: %{}, organization: current_org},
            %{membership: %{}, organization: other_org}
          ]
        )
        |> menu()
        |> Map.fetch!("organization")

      switcher = organization["switcher"]
      assert organization["label"]["text"] == "ORGANIZATION"
      assert switcher["summary"]["label"] == "Acme Space"

      assert [%{"key" => other_org_id, "label" => "Beta Labs", "form" => form}] =
               switcher["organizations"]

      assert other_org_id == other_org.organization_id
      fields = hidden_fields(form)
      assert form["attrs"] == %{"action" => "/session/organization", "method" => "post"}
      assert fields["_method"]["value"] == "put"
      assert fields["organization_id"]["value"] == other_org.organization_id
      refute fields["organization_id"]["value"] == current_org.organization_id
      assert is_binary(fields["_csrf_token"]["value"])
      assert fields["_csrf_token"]["value"] != ""
    end

    test "preserves switcher option filtering and membership order" do
      current_org = org_fixture(%{display_name: "Acme Space"})
      beta_org = org_fixture(%{display_name: "Beta Labs"})
      gamma_org = org_fixture(%{display_name: "Gamma Flight"})

      organizations =
        render_user_menu(
          scope: scope(user_fixture(), current_org),
          memberships: [
            %{membership: %{}, organization: beta_org},
            %{membership: %{}, organization: current_org},
            %{membership: %{}, organization: gamma_org}
          ]
        )
        |> menu()
        |> get_in(["organization", "switcher", "organizations"])

      assert Enum.map(organizations, & &1["key"]) == [
               beta_org.organization_id,
               gamma_org.organization_id
             ]
    end

    test "does not render the system administration link when platform_admin? is false" do
      menu = render_user_menu() |> menu()

      assert menu["admin_action"] == nil
      assert menu["leave_admin_mode"] == nil
    end

    test "renders the admin-mode entry link for an eligible user" do
      menu = render_user_menu(platform_admin?: true) |> menu()
      admin_action = menu["admin_action"]

      assert admin_action["label"] == "Enter admin mode"
      assert admin_action["attrs"]["href"] == "/admin-mode"
      assert admin_action["attrs"]["role"] == "menuitem"
      assert admin_action["attrs"]["data-phx-link"] == "redirect"
      assert admin_action["attrs"]["data-phx-link-state"] == "push"
      assert menu["leave_admin_mode"] == nil
    end

    test "renders administration and exit actions while admin mode is active" do
      admin_scope = %{scope(user_fixture()) | admin_mode?: true}
      menu = render_user_menu(scope: admin_scope, platform_admin?: true) |> menu()
      exit_form = menu["leave_admin_mode"]
      fields = hidden_fields(exit_form)

      assert menu["admin_action"]["label"] == "System administration"
      assert menu["admin_action"]["attrs"]["href"] == "/admin"
      assert exit_form["attrs"] == %{"action" => "/admin-mode", "method" => "post"}
      assert exit_form["button"]["label"] == "Leave admin mode"
      assert fields["_method"]["value"] == "delete"
      assert is_binary(fields["_csrf_token"]["value"])
      assert fields["_csrf_token"]["value"] != ""
    end

    test "identity block wrapper is a div so it doesn't trigger menu hover" do
      identity = render_user_menu() |> menu() |> Map.fetch!("identity")

      assert identity["element"] == "div"
      assert identity["attrs"] == %{"role" => "presentation"}
      assert identity["label"]["text"] == "Jane Rost"
    end

    test "organization block wrapper is a div so it doesn't trigger menu hover" do
      org = org_fixture(%{display_name: "Acme Space"})

      organization =
        render_user_menu(
          scope: scope(user_fixture(), org),
          memberships: [%{membership: %{}, organization: org}]
        )
        |> menu()
        |> Map.fetch!("organization")

      assert organization["element"] == "div"
      assert organization["attrs"] == %{"role" => "presentation"}
      assert organization["label"]["text"] == "ORGANIZATION"
    end

    test "identity block falls back to email when display_name is blank" do
      vue = render_user_menu(scope: scope(user_fixture(%{display_name: ""})))
      presentation = vue.props["presentation"]
      identity = presentation["menu"]["identity"]

      assert presentation["trigger"]["label"]["text"] == "jane@example.com"
      assert identity["label"]["text"] == "jane@example.com"
      assert identity["email"] == nil
    end

    test "emits a JSON-safe LiveVue host and presentation DTO" do
      vue = render_user_menu()

      assert vue.component == "UserMenu"
      assert vue.class == "contents"
      refute vue.ssr
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    end
  end
end
