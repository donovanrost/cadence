defmodule CadenceWeb.UserSessionLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  describe "GET /sign-in" do
    test "renders the sign-in form with title and brand", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      assert html =~ "Cadence"
      assert html =~ "Sign in"
      assert html =~ ~s(id="sign-in-form")
      assert html =~ "email"
      assert html =~ "password"
    end

    test "mounts the LiveToast host in the shared auth layout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#toast-group[data-live-toast-group='true']")
      assert has_element?(view, "#toast-group #client-error[phx-hook='LiveToast']")
      assert has_element?(view, "#toast-group #server-error[phx-hook='LiveToast']")
    end

    test "renders no setup-access-specific UI", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/sign-in")

      refute html =~ "setup-access-sign-in-form"
      refute html =~ "Temporary Access"
      refute html =~ "Setup Password"
    end

    test "form posts to the controller action", %{conn: conn} do
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
