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
  end
end
