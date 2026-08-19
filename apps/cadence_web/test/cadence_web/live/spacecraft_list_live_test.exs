defmodule CadenceWeb.SpacecraftListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders empty state when there are no spacecraft" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "No spacecraft"
      assert html =~ ~p"/missions/#{mission.mission_id}/spacecraft/new"
    end

    test "renders spacecraft in the vehicles management card" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _s1 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      s2 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-2")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(view, "#spacecraft-vehicles-card td", "Alpha-1")
      assert has_element?(view, "#spacecraft-vehicles-card td", "Alpha-2")
      assert has_element?(view, "#spacecraft-vehicles-card td", "101")
      assert has_element?(view, "#spacecraft-vehicles-card td", "Not set")

      assert has_element?(
               view,
               "#spacecraft-vehicles-card a[href='/missions/#{mission.mission_id}/spacecraft/new']",
               "New spacecraft"
             )

      assert has_element?(
               view,
               "#spacecraft-vehicles-card a[href='/missions/#{mission.mission_id}/spacecraft/#{s2.spacecraft_id}/identity']"
             )
    end

    test "shows only spacecraft belonging to this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      _mine = TestFixtures.persist_spacecraft!(mission, display_name: "Mine-1")
      _theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Theirs-1")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "Mine-1"
      refute html =~ "Theirs-1"
    end

    test "shows only spacecraft belonging to the current organization" do
      {conn, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      _theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Other-Org-Craft")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      refute html =~ "Other-Org-Craft"
    end
  end

  describe "fleet-scale roster" do
    test "name cell links to the spacecraft show page" do
      {conn, _org, mission} = signed_in_org_and_mission()
      craft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(
               view,
               "#spacecraft-vehicles-card a[href='/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}']",
               "Alpha-1"
             )
    end

    test "search narrows the roster" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _a = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      _b = TestFixtures.persist_spacecraft!(mission, display_name: "Bravo-2", scid: 202)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      html =
        view
        |> element("#spacecraft-roster-toolbar form")
        |> render_change(%{"q" => "Bravo"})

      refute html =~ "Alpha-1"
      assert has_element?(view, "#spacecraft-vehicles-card td", "Bravo-2")
    end

    test "filter tiles patch to a filtered roster" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _with_scid = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      _without = TestFixtures.persist_spacecraft!(mission, display_name: "No-Scid")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(
               view,
               "#spacecraft-setup-summary a[href*='filter=missing_scid']"
             )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?filter=missing_scid")

      assert has_element?(view, "#spacecraft-vehicles-card td", "No-Scid")
      refute has_element?(view, "#spacecraft-vehicles-card td", "Alpha-1")
      assert has_element?(view, "#spacecraft-tile-missing-scid[aria-current='true']")
    end

    test "sorts by SCID descending via the header button" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _low = TestFixtures.persist_spacecraft!(mission, display_name: "Low", scid: 1)
      _high = TestFixtures.persist_spacecraft!(mission, display_name: "High", scid: 900)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?sort=scid&dir=desc")

      html = render(view)
      high_at = :binary.match(html, "High") |> elem(0)
      low_at = :binary.match(html, "Low") |> elem(0)
      assert high_at < low_at
      assert has_element?(view, "th[aria-sort='descending']")
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

      assert has_element?(view, "#spacecraft-roster-pagination", "1–50 of 51")
      assert has_element?(view, "#spacecraft-vehicles-card td", "SC-001")
      refute has_element?(view, "#spacecraft-vehicles-card td", "SC-051")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?page=2")

      assert has_element?(view, "#spacecraft-roster-pagination", "51–51 of 51")
      assert has_element?(view, "#spacecraft-vehicles-card td", "SC-051")
      refute has_element?(view, "#spacecraft-vehicles-card td", "SC-001")
    end

    test "filtered-empty roster keeps the table copy, not the empty-mission state" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _craft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft?filter=missing_scid")

      assert has_element?(
               view,
               "#spacecraft-vehicles-card",
               "No spacecraft match the current search or filter."
             )

      refute has_element?(view, "#spacecraft-vehicles-card", "No spacecraft yet")
    end
  end
end
