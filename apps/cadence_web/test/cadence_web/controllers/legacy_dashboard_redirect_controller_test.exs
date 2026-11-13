defmodule CadenceWeb.LegacyDashboardRedirectControllerTest do
  @moduledoc "L8 cutover: the legacy dashboards directory, viewer, editor and New go to the console."
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

  test "the pages the console doesn't have yet stay on the legacy routes", c do
    for path <- ["/library", "/playlists", "/dash-1/settings", "/dash-1/activity"] do
      assert get(c.conn, c.legacy <> path).status == 200
    end
  end
end
