defmodule CadenceWeb.LegacyMissionSetupRedirectControllerTest do
  @moduledoc "§11c (B): legacy mission setup pages moved to the console (DECISIONS #79)."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    other = TestFixtures.persist_mission!(TestFixtures.persist_org!())

    %{
      conn: TestFixtures.member_conn(user),
      legacy: "/missions/#{mission.mission_id}",
      other: "/missions/#{other.mission_id}",
      console: "/console/#{org.slug}/#{mission.slug}"
    }
  end

  test "another organization's mission falls back to the console's home", c do
    assert redirected_to(get(c.conn, c.other)) == "/console"
  end

  test "B1: the mission home goes to the console mission", c do
    assert redirected_to(get(c.conn, c.legacy <> "")) == c.console <> ""
  end

  test "B2: mission settings and a section go to Setup settings", c do
    assert redirected_to(get(c.conn, c.legacy <> "/settings")) == c.console <> "/setup/settings"

    assert redirected_to(get(c.conn, c.legacy <> "/settings/cadence.governance")) ==
             c.console <> "/setup/settings/cadence.governance"
  end
end
