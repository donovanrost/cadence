defmodule CadenceWeb.UITest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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

  describe "user_menu/1" do
    test "renders display_name as trigger text" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      assert html =~ "Jane Rost"
    end

    test "renders identity block with name and email" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      assert html =~ "Jane Rost"
      assert html =~ "jane@example.com"
    end

    test "always renders sign-out form targeting DELETE /session" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      assert html =~ ~s|action="/session"|
      assert html =~ ~s|name="_method"|
      assert html =~ ~s|value="delete"|
      assert html =~ "Sign out"
    end

    test "omits the organization block entirely when scope.organization is nil" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      refute html =~ "ORGANIZATION"
    end

    test "renders label-only org row for single-membership users" do
      org = org_fixture(%{display_name: "Acme Space"})
      membership_map = %{membership: %{}, organization: org}

      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture(), org),
          memberships: [membership_map],
          platform_admin?: false
        )

      assert html =~ "ORGANIZATION"
      assert html =~ "Acme Space"
      refute html =~ "<details"
      refute html =~ ~s|action="/session/organization"|
    end

    test "renders expandable switcher for multi-membership users" do
      current_org = org_fixture(%{display_name: "Acme Space"})
      other_org = org_fixture(%{display_name: "Beta Labs"})

      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture(), current_org),
          memberships: [
            %{membership: %{}, organization: current_org},
            %{membership: %{}, organization: other_org}
          ],
          platform_admin?: false
        )

      assert html =~ "ORGANIZATION"
      assert html =~ "Acme Space"
      assert html =~ "Beta Labs"
      assert html =~ ~s|action="/session/organization"|
      assert html =~ ~s|name="_method"|
      assert html =~ ~s|value="put"|
      assert html =~ ~s|name="organization_id"|
      assert html =~ ~s|value="#{other_org.organization_id}"|
      refute html =~ ~s|value="#{current_org.organization_id}"|
    end

    test "does not render the system administration link when platform_admin? is false" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      refute html =~ "System administration"
    end

    test "renders the system administration link when platform_admin? is true" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: true
        )

      assert html =~ "System administration"
      assert html =~ ~s|href="/admin"|
    end

    test "identity block wrapper is a div so it doesn't trigger menu hover" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      # The identity block lives inside a <div role="presentation"> (not <li>),
      # so daisyUI's .menu > li > * hover selector doesn't reach the name/email.
      assert html =~ ~r|<div role="presentation"[^>]*>\s*<p[^>]*>\s*Jane Rost|
    end

    test "organization block wrapper is a div so it doesn't trigger menu hover" do
      org = org_fixture(%{display_name: "Acme Space"})

      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture(), org),
          memberships: [%{membership: %{}, organization: org}],
          platform_admin?: false
        )

      # The org block lives inside a <div role="presentation"> (not <li>),
      # so daisyUI's hover selector doesn't reach the ORGANIZATION label or the
      # single-org display name.
      assert html =~ ~r|<div role="presentation"[^>]*>\s*<span class="hud-label|
    end

    test "identity block falls back to email when display_name is blank" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture(%{display_name: ""})),
          memberships: [],
          platform_admin?: false
        )

      # Email appears in the identity block's primary slot.
      assert html =~ "jane@example.com"
      # No stray empty primary name paragraph.
      refute html =~ ~r|<p class="text-sm font-semibold text-base-content">\s*</p>|
      # The secondary email <p> is suppressed when display_name is blank — so
      # email renders exactly once in the identity block (no duplicate line).
      refute html =~ ~r|<p class="text-xs text-base-content/50 truncate">\s*</p>|

      assert html
             |> String.split("jane@example.com")
             |> length()
             |> Kernel.-(1) == 2

      # Trigger also falls back to email rather than showing an empty span.
      refute html =~ ~r|<span class="text-xs text-base-content/60">\s*</span>|
    end
  end
end
