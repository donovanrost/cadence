defmodule CadenceWeb.UserSessionLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  describe "GET /sign-in" do
    test "renders the single sign-in form with hero header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Cadence Access"
      assert html =~ "Sign In"
      assert html =~ "email"
      assert html =~ "password"
      # One <form> tag, not two.
      assert html |> String.split("<form") |> length() == 2
    end

    test "renders no setup-access-specific UI", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      refute html =~ "setup-access-sign-in-form"
      refute html =~ "Temporary Access"
      refute html =~ "Setup Password"
    end

    test "form posts to the controller action at ~p\"/sign-in\"", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ ~s(action="/sign-in")
    end

    test "phx-change updates the form assigns without error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      updated =
        view
        |> form("#sign-in-form", user: %{email: "ops@example.com", password: "in-progress"})
        |> render_change()

      assert updated =~ ~s(value="ops@example.com")
    end
  end
end

# Flash rendering on redirect from the controller is covered by
# browser_shell_test.exs — the POST → redirect → LiveView mount path
# exercises it end-to-end.
