defmodule CadenceWeb.UITest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CadenceWeb.UI

  defp scope(user, organization \\ nil) do
    %Cadence.Auth.Scope{user: user, organization: organization, capabilities: MapSet.new()}
  end

  defp user_fixture(attrs \\ %{}) do
    Cadence.Accounts.User.new(
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
    Cadence.Organizations.Organization.new(
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
  end
end
