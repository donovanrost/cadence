defmodule CadenceWeb.LiveVuePocLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.{LiveVuePocLive, TestFixtures}

  test "the organization-scoped authenticated route renders one JSON-safe LiveVue parent" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)

    {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/livevue-poc")

    assert has_element?(view, "#livevue-poc-page-component.contents")
    refute has_element?(view, "#livevue-poc-page")
    refute has_element?(view, "#livevue-poc-component")

    vue = LiveVue.Test.get_vue(view, id: "livevue-poc-page-component")

    assert vue.component == "LiveVuePocPage"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props["presentation"] == %{
             "root" => %{
               "attrs" => %{"id" => "livevue-poc-page", "class" => "space-y-6"}
             },
             "header" => %{
               "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
               "body" => %{"attrs" => %{}},
               "content" => %{"attrs" => %{}},
               "title" => %{
                 "attrs" => %{
                   "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
                 },
                 "text" => "LiveVue PoC"
               },
               "subtitle" => %{
                 "attrs" => %{
                   "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
                 },
                 "text" =>
                   "A Vue component mounted inside the authenticated Cadence LiveView shell."
               }
             },
             "demo" => %{
               "attrs" => %{"id" => "livevue-poc-component"},
               "message" => "Vue is mounted inside a Cadence LiveView"
             }
           }
  end

  test "the PoC route requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/livevue-poc")
  end

  test "presentation attrs preserve HEEx coercion semantics" do
    assert LiveVuePocLive.presentation_attrs(%{
             "data-nil" => nil,
             "data-false" => false,
             "data-true" => true,
             "data-empty" => "",
             "data-string" => "retained",
             "data-number" => 42
           }) == %{
             "data-true" => "",
             "data-empty" => "",
             "data-string" => "retained",
             "data-number" => "42"
           }
  end
end
