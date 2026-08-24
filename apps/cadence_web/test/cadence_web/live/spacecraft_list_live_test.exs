defmodule CadenceWeb.SpacecraftListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.SpacecraftListLive
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp spacecraft_list_props(view) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-list-component")
    assert vue.component == "SpacecraftListPage"
    assert vue.class == "contents"
    refute vue.ssr
    assert Map.keys(vue.props) == ["presentation"]
    vue.props["presentation"]
  end

  describe "mount" do
    test "renders empty state when there are no spacecraft" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(view, "#spacecraft-list-component")

      props = spacecraft_list_props(view)

      assert props["roster"]["fleet_empty"]

      assert props["roster"]["new_spacecraft_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/new"

      assert props["profiles"]["empty"]
    end

    test "renders spacecraft through JSON-safe roster props" do
      {conn, _org, mission} = signed_in_org_and_mission()
      s1 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      s2 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-2")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      props = spacecraft_list_props(view)

      assert props["roster"]["new_spacecraft_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/new"

      assert props["roster"]["rows"] == [
               %{
                 "id" => "spacecraft-#{s1.spacecraft_id}",
                 "actions_id" => "#{s1.spacecraft_id}-actions",
                 "display_name" => "Alpha-1",
                 "scid_label" => "101",
                 "scid_missing" => false,
                 "profile_label" => "Not selected",
                 "status" => "attention",
                 "status_label" => "Needs profile",
                 "href" => "/missions/#{mission.mission_id}/spacecraft/#{s1.spacecraft_id}",
                 "identity_href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{s1.spacecraft_id}/identity"
               },
               %{
                 "id" => "spacecraft-#{s2.spacecraft_id}",
                 "actions_id" => "#{s2.spacecraft_id}-actions",
                 "display_name" => "Alpha-2",
                 "scid_label" => "Not set",
                 "scid_missing" => true,
                 "profile_label" => "Not selected",
                 "status" => "attention",
                 "status_label" => "Needs SCID",
                 "href" => "/missions/#{mission.mission_id}/spacecraft/#{s2.spacecraft_id}",
                 "identity_href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{s2.spacecraft_id}/identity"
               }
             ]
    end

    test "shows only spacecraft belonging to this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      mine = TestFixtures.persist_spacecraft!(mission, display_name: "Mine-1")
      theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Theirs-1")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      rows = spacecraft_list_props(view)["roster"]["rows"]

      assert Enum.map(rows, & &1["id"]) == ["spacecraft-#{mine.spacecraft_id}"]
      refute Enum.any?(rows, &(&1["id"] == "spacecraft-#{theirs.spacecraft_id}"))
      refute Enum.any?(rows, &(&1["display_name"] == "Theirs-1"))
    end

    test "shows only spacecraft belonging to the current organization" do
      {conn, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Other-Org-Craft")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      rows = spacecraft_list_props(view)["roster"]["rows"]

      refute Enum.any?(rows, &(&1["id"] == "spacecraft-#{theirs.spacecraft_id}"))
      refute Enum.any?(rows, &(&1["display_name"] == "Other-Org-Craft"))
    end
  end

  describe "fleet-scale roster" do
    test "name cell links to the spacecraft show page" do
      {conn, _org, mission} = signed_in_org_and_mission()
      craft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      [row] = spacecraft_list_props(view)["roster"]["rows"]

      assert row["display_name"] == "Alpha-1"
      assert row["href"] == "/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}"
    end

    test "search narrows the roster" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _a = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      _b = TestFixtures.persist_spacecraft!(mission, display_name: "Bravo-2", scid: 202)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      render_hook(view, "search", %{"q" => "Bravo"})

      roster = spacecraft_list_props(view)["roster"]

      assert roster["search"] == "Bravo"
      assert Enum.map(roster["rows"], & &1["display_name"]) == ["Bravo-2"]
      refute Enum.any?(roster["rows"], &(&1["display_name"] == "Alpha-1"))
    end

    test "filter tiles patch to a filtered roster" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _with_scid = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      _without = TestFixtures.persist_spacecraft!(mission, display_name: "No-Scid")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      props = spacecraft_list_props(view)

      missing_scid_tile =
        Enum.find(props["summary_tiles"], &(&1["id"] == "spacecraft-tile-missing-scid"))

      assert missing_scid_tile["href"] =~ "filter=missing_scid"

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?filter=missing_scid")

      props = spacecraft_list_props(view)

      missing_scid_tile =
        Enum.find(props["summary_tiles"], &(&1["id"] == "spacecraft-tile-missing-scid"))

      assert Enum.map(props["roster"]["rows"], & &1["display_name"]) == ["No-Scid"]
      refute Enum.any?(props["roster"]["rows"], &(&1["display_name"] == "Alpha-1"))
      assert missing_scid_tile["active"]
    end

    test "sorts by SCID descending via the header button" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _low = TestFixtures.persist_spacecraft!(mission, display_name: "Low", scid: 1)
      _high = TestFixtures.persist_spacecraft!(mission, display_name: "High", scid: 900)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?sort=scid&dir=asc")

      render_hook(view, "sort", %{"sort" => "scid"})

      roster = spacecraft_list_props(view)["roster"]

      assert roster["sort_by"] == "scid"
      assert roster["sort_dir"] == "desc"
      assert Enum.map(roster["rows"], & &1["display_name"]) == ["High", "Low"]
    end

    test "paginates past fifty spacecraft" do
      {conn, _org, mission} = signed_in_org_and_mission()

      for n <- 1..51 do
        TestFixtures.persist_spacecraft!(mission,
          display_name: "SC-#{String.pad_leading(Integer.to_string(n), 3, "0")}",
          scid: n
        )
      end

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      roster = spacecraft_list_props(view)["roster"]

      assert roster["pagination_visible"]
      assert roster["range_label"] == "1–50 of 51"
      assert List.first(roster["rows"])["display_name"] == "SC-001"
      refute Enum.any?(roster["rows"], &(&1["display_name"] == "SC-051"))

      render_hook(view, "paginate", %{"page" => "2"})

      roster = spacecraft_list_props(view)["roster"]

      assert roster["page"] == 2
      assert roster["range_label"] == "51–51 of 51"
      assert Enum.map(roster["rows"], & &1["display_name"]) == ["SC-051"]
      refute Enum.any?(roster["rows"], &(&1["display_name"] == "SC-001"))
    end

    test "filtered-empty roster keeps the table copy, not the empty-mission state" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _craft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?filter=missing_scid")

      roster = spacecraft_list_props(view)["roster"]

      assert roster["filtered_empty"]
      refute roster["fleet_empty"]
      assert roster["rows"] == []
    end
  end

  describe "page presentation" do
    test "projects the complete page through one JSON-safe non-SSR parent" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      presentation = spacecraft_list_props(view)
      assert presentation == Jason.decode!(Jason.encode!(presentation))

      assert presentation["root"] == %{
               "attrs" => %{
                 "class" => "space-y-6",
                 "id" => "spacecraft-management-page"
               }
             }

      assert presentation["header"] == %{
               "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
               "body" => %{"attrs" => %{}},
               "content" => %{"attrs" => %{}},
               "title" => %{
                 "attrs" => %{
                   "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
                 },
                 "text" => "Spacecraft"
               },
               "subtitle" => %{
                 "attrs" => %{
                   "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
                 },
                 "text" =>
                   "Manage mission spacecraft identities and reusable spacecraft profiles."
               }
             }

      assert presentation["breadcrumbs"]["attrs"] == %{
               "aria-label" => "Breadcrumb",
               "class" =>
                 "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
             }

      assert Enum.map(presentation["breadcrumbs"]["items"], fn item ->
               (item["link"] && item["link"]["text"]) || item["current"]["text"]
             end) == [mission.display_name, "Spacecraft"]

      assert Enum.map(presentation["breadcrumbs"]["items"], fn item ->
               item["link"] && item["link"]["attrs"]["href"]
             end) == ["/missions/#{mission.mission_id}", nil]

      mission_link = List.first(presentation["breadcrumbs"]["items"])["link"]["attrs"]
      assert mission_link["data-phx-link"] == "redirect"
      assert mission_link["data-phx-link-state"] == "push"

      assert is_list(presentation["summary_tiles"])
      assert is_map(presentation["roster"])
      assert is_map(presentation["profiles"])
    end

    test "raw attrs preserve HEEx nil, false, true, string, and number semantics" do
      attrs =
        SpacecraftListLive.presentation_attrs(%{
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
end
