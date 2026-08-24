defmodule CadenceWeb.OrganizationHomeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.{OrganizationHomeLive, TestFixtures}

  describe "mount" do
    test "renders org display_name and slug" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
      _membership = TestFixtures.grant_membership!(user, org)

      conn = TestFixtures.member_conn(user)

      {:ok, view, _html} = live(conn, ~p"/")
      presentation = organization_home_presentation(view)

      assert presentation["header"]["title"]["text"] == "Cadence Ops"
      assert presentation["header"]["subtitle"]["text"] == "cadence-ops"
    end

    test "sidebar highlights the Home nav item" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org)

      {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/")

      sidebar = LiveVue.Test.get_vue(view, id: "global-sidebar-navigation")

      home =
        Enum.find(
          sidebar.props["presentation"]["navigation"]["items"],
          &(&1["key"] == "organization-home")
        )

      assert home["label"] == "Home"
      assert home["class"] =~ "border-primary"
    end

    test "shows the current mission count and link to /missions" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _ = TestFixtures.grant_membership!(user, org)

      mission =
        Mission.new(%{
          organization_id: org.organization_id,
          slug: "alpha",
          display_name: "Alpha"
        })

      assert {:ok, _} = Cadence.Missions.persist_mission(mission)

      {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/")
      presentation = organization_home_presentation(view)

      assert presentation["recent_missions"]["header"]["all_missions"] == %{
               "attrs" => %{
                 "class" => "btn btn-ghost btn-sm",
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push",
                 "href" => "/missions"
               },
               "text" => "All missions"
             }

      assert presentation["stats"]["mission_count"] == 1
    end

    test "lists recent missions with status badges" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _ = TestFixtures.grant_membership!(user, org)

      mission =
        Mission.new(%{
          organization_id: org.organization_id,
          slug: "alpha",
          display_name: "Alpha Mission"
        })

      assert {:ok, _} = Cadence.Missions.persist_mission(mission)

      {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/")
      presentation = organization_home_presentation(view)

      assert presentation["recent_missions"]["card"]["attrs"]["id"] ==
               "organization-recent-missions"

      assert presentation["recent_missions"]["rows"] == [
               %{
                 "id" => "organization-recent-mission-#{mission.mission_id}",
                 "display_name" => "Alpha Mission",
                 "slug" => "alpha",
                 "status" => "info",
                 "status_label" => "No spacecraft",
                 "href" => "/missions/#{mission.mission_id}"
               }
             ]
    end
  end

  describe "presentation" do
    test "projects the complete empty page through one JSON-safe non-SSR parent" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Empty Ops", slug: "empty-ops")
      _membership = TestFixtures.grant_membership!(user, org)

      {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/")

      vue = LiveVue.Test.get_vue(view, id: "organization-home-component")
      assert vue.component == "OrganizationHome"
      refute vue.ssr
      assert Map.keys(vue.props) == ["presentation"]

      presentation = vue.props["presentation"]
      assert presentation == Jason.decode!(Jason.encode!(presentation))

      assert presentation["root"] == %{"attrs" => %{"class" => "space-y-6"}}

      assert presentation["header"] == %{
               "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
               "body" => %{"attrs" => %{}},
               "content" => %{"attrs" => %{}},
               "title" => %{
                 "attrs" => %{
                   "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
                 },
                 "text" => "Empty Ops"
               },
               "subtitle" => %{
                 "attrs" => %{
                   "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
                 },
                 "text" => "empty-ops"
               }
             }

      assert presentation["stats"] == %{
               "member_count" => 1,
               "mission_count" => 0,
               "spacecraft_count" => 0
             }

      recent = presentation["recent_missions"]
      assert recent["rows"] == []
      assert recent["card"]["attrs"]["id"] == "organization-recent-missions"
      assert recent["header"]["eyebrow"]["text"] == "Recent Missions"
      assert recent["header"]["title"]["text"] == "Jump into a mission"

      assert recent["empty_state"]["title"]["text"] == "No missions yet"

      assert recent["empty_state"]["description"]["text"] ==
               "Create your first mission to get started."

      assert recent["empty_state"]["icon"]["attrs"]["class"] ==
               "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block"

      assert recent["empty_state"]["action"] == %{
               "attrs" => %{
                 "class" => "btn btn-primary btn-sm",
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push",
                 "href" => "/missions/new"
               },
               "text" => "New Mission"
             }
    end

    test "keeps recent ordering, limit, status derivation, and counts server-owned" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org)

      delta = TestFixtures.persist_mission!(org, slug: "delta", display_name: "Delta")
      charlie = TestFixtures.persist_mission!(org, slug: "charlie", display_name: "Charlie")
      bravo = TestFixtures.persist_mission!(org, slug: "bravo", display_name: "Bravo")
      alpha = TestFixtures.persist_mission!(org, slug: "alpha", display_name: "Alpha")

      _ready = TestFixtures.persist_spacecraft!(bravo, display_name: "Ready Craft", scid: 42)
      _attention = TestFixtures.persist_spacecraft!(charlie, display_name: "Needs SCID")

      {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/")
      presentation = organization_home_presentation(view)
      rows = presentation["recent_missions"]["rows"]

      assert Enum.map(rows, & &1["id"]) == [
               "organization-recent-mission-#{alpha.mission_id}",
               "organization-recent-mission-#{bravo.mission_id}",
               "organization-recent-mission-#{charlie.mission_id}"
             ]

      assert Enum.map(rows, &{&1["status"], &1["status_label"]}) == [
               {"info", "No spacecraft"},
               {"ready", "Ready"},
               {"attention", "Needs setup"}
             ]

      refute Enum.any?(rows, &(&1["id"] == "organization-recent-mission-#{delta.mission_id}"))
      assert presentation["recent_missions"]["empty_state"] == nil

      assert presentation["stats"] == %{
               "member_count" => 1,
               "mission_count" => 4,
               "spacecraft_count" => 2
             }
    end

    test "raw attrs preserve HEEx nil, false, true, string, and number semantics" do
      attrs =
        OrganizationHomeLive.presentation_attrs(%{
          "nil" => nil,
          "false" => false,
          "true" => true,
          "string" => "retained",
          "number" => 7
        })

      assert attrs == %{
               "true" => "",
               "string" => "retained",
               "number" => "7"
             }
    end
  end

  describe "authorization" do
    test "active admin mode redirects to /admin even from /" do
      user =
        TestFixtures.persist_user!(
          email: "elevated-admin-root@example.com",
          capabilities: [:platform_admin]
        )

      token = TestFixtures.member_session_token!(user)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{
          user_session_token: token,
          admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
        })

      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/")
    end
  end

  defp organization_home_presentation(view) do
    vue = LiveVue.Test.get_vue(view, id: "organization-home-component")

    assert vue.component == "OrganizationHome"
    refute vue.ssr
    assert Map.keys(vue.props) == ["presentation"]

    vue.props["presentation"]
  end
end
