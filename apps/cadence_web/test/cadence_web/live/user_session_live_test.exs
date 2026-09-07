defmodule CadenceWeb.UserSessionLiveTest do
  use CadenceWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias LiveVue.Test

  test "sign-in bootstraps only its session transport", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/sign-in")
    vue = Test.get_vue(view, id: "user-session-component")
    assert vue.component == "UserSession"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["csrf-token"]
    assert is_binary(vue.props["csrf-token"])
    assert vue.props["csrf-token"] != ""
    assert Test.get_vue(view, id: "application-shell").props["variant"] == "auth"
    assert has_element?(view, "#user-session-component[data-name=UserSession]")
  end

  test "keeps the connection and flash transport in the auth boundary", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/sign-in")
    assert has_element?(view, "#toast-group[data-live-toast-group='true']")
    assert has_element?(view, "#toast-group #client-error[phx-hook='LiveToast']")
    assert has_element?(view, "#toast-group #server-error[phx-hook='LiveToast']")
  end
end
