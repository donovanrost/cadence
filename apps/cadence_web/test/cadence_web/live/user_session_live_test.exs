defmodule CadenceWeb.UserSessionLiveTest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias LiveVue.Test
  alias Phoenix.LiveView.JS

  describe "GET /sign-in" do
    test "renders the sign-in form with title and brand", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      brand_vue = auth_layout_brand_vue(view)

      assert brand_vue.props["presentation"] == %{
               "link" => %{
                 "attrs" => %{"href" => "/"},
                 "class" =>
                   "inline-block font-mono text-sm tracking-[0.28em] uppercase text-primary",
                 "label" => "Cadence"
               },
               "tagline" => %{
                 "class" => "mt-1 text-xs text-base-content/50",
                 "text" => "Ground data control plane"
               }
             }

      refute has_element?(view, "#user-session-component a[href='/']")

      vue = user_session_vue(view)

      assert vue.props["page"] == %{
               "access_help" => "Need access? Contact your organization admin.",
               "body" => "Enter your operator credentials to access the control plane.",
               "brand" => "◆ CADENCE",
               "heading" => "Sign in",
               "id" => "user-session-page"
             }

      assert vue.props["form"]["fields"]["email"] == %{
               "autocomplete" => "email",
               "autofocus" => true,
               "id" => "user_email",
               "label" => "Email",
               "name" => "user[email]",
               "placeholder" => "operator@example.com",
               "required" => true,
               "type" => "email",
               "value" => ""
             }

      assert vue.props["form"]["fields"]["password"] == %{
               "autocomplete" => "current-password",
               "autofocus" => false,
               "id" => "user_password",
               "label" => "Password",
               "name" => "user[password]",
               "placeholder" => "Enter your password",
               "required" => true,
               "type" => "password",
               "value" => ""
             }

      assert vue.props["form"]["submit"] == %{
               "id" => "sign-in-submit",
               "label" => "Sign In"
             }
    end

    test "mounts the LiveToast host in the shared auth layout", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#toast-group[data-live-toast-group='true']")
      assert has_element?(view, "#toast-group #client-error[phx-hook='LiveToast']")
      assert has_element?(view, "#toast-group #server-error[phx-hook='LiveToast']")
      refute has_element?(view, "#user-session-component #toast-group")
    end

    test "renders no setup-access-specific UI", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      refute has_element?(view, "#setup-access-sign-in-form")
      refute has_element?(view, "div", "Temporary Access")
      refute has_element?(view, "div", "Setup Password")

      encoded_props = view |> user_session_vue() |> Map.fetch!(:props) |> Jason.encode!()

      refute encoded_props =~ "setup-access"
      refute encoded_props =~ "Temporary Access"
      refute encoded_props =~ "Setup Password"
    end

    test "form posts to the controller action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      form = user_session_vue(view).props["form"]

      assert form["id"] == "sign-in-form"
      assert form["action"] == "/sign-in"
      assert form["method"] == "post"
      assert form["csrf"]["name"] == "_csrf_token"
      assert is_binary(form["csrf"]["value"])
      assert form["csrf"]["value"] != ""
    end

    test "phx-change updates the form assigns without error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      payload = %{
        "user" => %{"email" => "ops@example.com", "password" => "in-progress"}
      }

      render_hook(view, "validate", payload)

      fields = user_session_vue(view).props["form"]["fields"]

      assert fields["email"]["value"] == "ops@example.com"
      assert fields["password"]["value"] == "in-progress"
    end
  end

  defp user_session_vue(view) do
    vue = Test.get_vue(view, id: "user-session-component")

    assert vue.component == "UserSession"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props |> Map.keys() |> Enum.sort() == ["form", "page"]
    assert vue.handlers == %{"validate" => JS.push("validate")}

    vue
  end

  defp auth_layout_brand_vue(view) do
    vue = Test.get_vue(view, id: "auth-layout-brand")

    assert vue.component == "AuthLayoutBrand"
    assert vue.class == "text-center"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert Map.keys(vue.props) == ["presentation"]

    vue
  end
end
