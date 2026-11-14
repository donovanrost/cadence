defmodule CadenceWeb.LegacyDashboardRedirectControllerTest do
  @moduledoc "L8 cutover: every legacy dashboards page goes to the console (L8a, L8b)."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission,
      legacy: "/missions/#{mission.mission_id}/ops/dashboards",
      console: "/console/#{org.slug}/#{mission.slug}/telemetry/dashboards"
    }
  end

  test "the directory goes to the console's, keeping its search and tag filters", c do
    assert redirected_to(get(c.conn, c.legacy)) == c.console

    assert redirected_to(get(c.conn, c.legacy <> "?query=thermal&tag=flight&junk=1")) ==
             c.console <> "?q=thermal&tags=flight"
  end

  test "the viewer keeps the time range, spacecraft, refresh and kiosk; nothing else", c do
    assert redirected_to(get(c.conn, c.legacy <> "/dash-1")) == c.console <> "/dash-1"

    assert redirected_to(
             get(
               c.conn,
               c.legacy <>
                 "/dash-1?from=now-6h&to=now&spacecraft_id=sc-1&refresh=5s&kiosk=1&stale=x"
             )
           ) == c.console <> "/dash-1?from=now-6h&kiosk=1&refresh=5s&spacecraft=sc-1&to=now"
  end

  test "the editor opens the console's viewer in edit mode, with the range", c do
    assert redirected_to(get(c.conn, c.legacy <> "/dash-1/edit")) ==
             c.console <> "/dash-1?edit=1"

    assert redirected_to(get(c.conn, c.legacy <> "/dash-1/edit?from=now-1h&to=now")) ==
             c.console <> "/dash-1?edit=1&from=now-1h&to=now"
  end

  test "New goes to the console's New (L8a)", c do
    assert redirected_to(get(c.conn, c.legacy <> "/new")) == c.console <> "/new"
  end

  test "another organization's mission goes to /console; signed out goes to sign in", c do
    other = TestFixtures.persist_mission!(TestFixtures.persist_org!())

    for path <- ["", "/new", "/dash-1", "/dash-1/edit"] do
      assert redirected_to(get(c.conn, "/missions/#{other.mission_id}/ops/dashboards" <> path)) ==
               "/console"
    end

    assert "/sign-in" <> _ = redirected_to(get(build_conn(), c.legacy))
  end

  test "L8b: library, playlists, present, and a dashboard's settings, activity and diagnostics",
       c do
    for {legacy, console} <- [
          {"/library", "/library"},
          {"/playlists", "/playlists"},
          {"/playlists/pl-1/present", "/playlists/pl-1/present"},
          {"/dash-1/settings", "/dash-1/settings"},
          {"/dash-1/activity", "/dash-1/settings/activity"},
          {"/dash-1/diagnostics", "/dash-1/settings/diagnostics"}
        ] do
      assert redirected_to(get(c.conn, c.legacy <> legacy)) == c.console <> console
    end
  end

  test "L8b: shares and snapshots keep the range and spacecraft, nothing else", c do
    base = "/missions/#{c.mission.mission_id}/ops"

    assert redirected_to(get(c.conn, base <> "/dashboard-shares/sh-1")) ==
             c.console <> "/shares/sh-1"

    assert redirected_to(
             get(c.conn, base <> "/dashboard-snapshots/sn-1?from=now-1h&to=now&kiosk=1")
           ) == c.console <> "/snapshots/sn-1?from=now-1h&to=now"
  end

  test "L8b: another organization's mission goes to /console; the legacy export is gone", c do
    other =
      "/missions/#{TestFixtures.persist_mission!(TestFixtures.persist_org!()).mission_id}/ops"

    for path <- ["/dashboards/library", "/dashboards/dash-1/activity", "/dashboard-shares/sh-1"] do
      assert redirected_to(get(c.conn, other <> path)) == "/console"
    end

    assert get(c.conn, c.legacy <> "/dash-1/export").status == 404
  end
end
