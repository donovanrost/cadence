defmodule CadenceWeb.UserSessionLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  describe "GET /sign-in" do
    test "renders the sign-in form with title and brand", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "a[href='/']", "Cadence")
      assert has_element?(view, "h1", "Sign in")
      assert has_element?(view, "#sign-in-form input[name='user[email]'][type='email']")
      assert has_element?(view, "#sign-in-form input[name='user[password]'][type='password']")
    end

    test "mounts the LiveToast host in the shared auth layout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#toast-group[data-live-toast-group='true']")
      assert has_element?(view, "#toast-group #client-error[phx-hook='LiveToast']")
      assert has_element?(view, "#toast-group #server-error[phx-hook='LiveToast']")
    end

    test "renders no setup-access-specific UI", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      refute has_element?(view, "#setup-access-sign-in-form")
      refute has_element?(view, "div", "Temporary Access")
      refute has_element?(view, "div", "Setup Password")
    end

    test "form posts to the controller action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#sign-in-form[action='/sign-in'][method='post']")
    end

    test "phx-change updates the form assigns without error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      view
      |> form("#sign-in-form", user: %{email: "ops@example.com", password: "in-progress"})
      |> render_change()

      assert has_element?(
               view,
               "#sign-in-form input[name='user[email]'][value='ops@example.com']"
             )
    end
  end
end
