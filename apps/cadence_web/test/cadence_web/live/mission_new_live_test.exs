defmodule CadenceWeb.MissionNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  describe "render" do
    test "renders the empty form" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      assert has_element?(view, "#mission-new-component")
      refute has_element?(view, "#mission-form")

      vue = mission_new_vue(view)

      assert vue.component == "MissionNew"
      assert vue.class == "space-y-6 max-w-xl"
      assert vue.ssr == false
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      assert vue.handlers == %{
               "save" => JS.push("save"),
               "validate" => JS.push("validate")
             }

      assert vue.props == %{
               "page" => %{
                 "id" => "mission-new-page",
                 "heading" => "New Mission",
                 "breadcrumbs" => [
                   %{"label" => "Missions", "href" => "/missions"},
                   %{"label" => "New Mission", "href" => nil}
                 ]
               },
               "form" => %{
                 "id" => "mission-form",
                 "fields" => %{
                   "display_name" => %{
                     "id" => "mission_display_name",
                     "name" => "mission[display_name]",
                     "type" => "text",
                     "label" => "Display Name",
                     "required" => true,
                     "value" => ""
                   },
                   "slug" => %{
                     "id" => "mission_slug",
                     "name" => "mission[slug]",
                     "type" => "text",
                     "label" => "Slug",
                     "required" => true,
                     "value" => ""
                   }
                 },
                 "actions" => %{
                   "submit" => %{
                     "id" => "create-mission-button",
                     "label" => "Create Mission"
                   },
                   "cancel" => %{
                     "id" => "cancel-mission-link",
                     "label" => "Cancel",
                     "href" => "/missions"
                   }
                 }
               }
             }
    end
  end

  describe "auto slug" do
    test "derives slug from display_name on validate when slug is empty" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      render_hook(view, "validate", %{
        "mission" => %{"display_name" => "Alpha Mission", "slug" => ""}
      })

      fields = mission_new_vue(view).props["form"]["fields"]

      assert fields["display_name"]["value"] == "Alpha Mission"
      assert fields["slug"]["value"] == "alpha-mission"
    end

    test "preserves user-entered slug even when display_name changes" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      render_hook(view, "validate", %{
        "mission" => %{"display_name" => "Foo", "slug" => "custom-slug"}
      })

      render_hook(view, "validate", %{
        "mission" => %{"display_name" => "Bar", "slug" => "custom-slug"}
      })

      fields = mission_new_vue(view).props["form"]["fields"]

      assert fields["display_name"]["value"] == "Bar"
      assert fields["slug"]["value"] == "custom-slug"
    end
  end

  describe "submit" do
    test "creates the mission and navigates to its show page" do
      {conn, org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      render_hook(view, "save", %{
        "mission" => %{"display_name" => " Alpha ", "slug" => " alpha "}
      })

      {redirect_path, _flash} = assert_redirect(view)
      assert redirect_path =~ ~r|^/missions/mission_|

      assert [mission] = Cadence.Missions.list_missions(org.organization_id)
      assert mission.slug == "alpha"
      assert mission.display_name == "Alpha"
    end

    test "flashes an error when display_name is blank after trimming" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      render_hook(view, "save", %{
        "mission" => %{"display_name" => "   ", "slug" => "alpha"}
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Display name is required."
             )
    end

    test "flashes an error when slug is blank after trimming" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      render_hook(view, "save", %{
        "mission" => %{"display_name" => "Alpha", "slug" => "   "}
      })

      assert has_element?(view, "#flash-error[role='alert']", "Slug is required.")
    end

    test "flashes a humanized error when slug is already taken" do
      {conn, org} = signed_in_conn()

      existing =
        Mission.new(%{
          organization_id: org.organization_id,
          slug: "alpha",
          display_name: "Alpha"
        })

      assert {:ok, _} = Cadence.Missions.persist_mission(existing)

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      render_hook(view, "save", %{
        "mission" => %{"display_name" => "Alpha Two", "slug" => "alpha"}
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Slug has already been taken"
             )
    end
  end

  defp mission_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "mission-new-component")
  end
end
