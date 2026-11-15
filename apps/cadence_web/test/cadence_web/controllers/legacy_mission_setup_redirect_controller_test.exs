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

  test "B3: the spacecraft list and New spacecraft go to Setup", c do
    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft")) ==
             c.console <> "/setup/spacecraft"

    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/new")) ==
             c.console <> "/setup/spacecraft/new"
  end

  test "B4: profiles, New profile and one profile go to Setup profiles", c do
    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/profiles")) ==
             c.console <> "/setup/profiles"

    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/profiles/new")) ==
             c.console <> "/setup/profiles/new"

    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/profiles/profile_1")) ==
             c.console <> "/setup/profiles/profile_1"
  end

  test "B6: the catalog, its import and a database go to the Setup catalog", c do
    assert redirected_to(get(c.conn, c.legacy <> "/catalog")) == c.console <> "/setup/catalog"

    assert redirected_to(get(c.conn, c.legacy <> "/catalog/new")) ==
             c.console <> "/setup/catalog/import"

    assert redirected_to(get(c.conn, c.legacy <> "/catalog/databases/db_1")) ==
             c.console <> "/setup/catalog/db_1"

    assert redirected_to(get(c.conn, c.legacy <> "/catalog/imports/run_1")) ==
             c.console <> "/setup/catalog/import/run_1"
  end

  test "B7: comms, transports, New transport and one transport go to Setup comms", c do
    assert redirected_to(get(c.conn, c.legacy <> "/comms")) == c.console <> "/setup/comms"

    assert redirected_to(get(c.conn, c.legacy <> "/comms/transports")) ==
             c.console <> "/setup/comms/transports"

    assert redirected_to(get(c.conn, c.legacy <> "/comms/transports/new")) ==
             c.console <> "/setup/comms/transports"

    assert redirected_to(get(c.conn, c.legacy <> "/comms/transports/tr_1")) ==
             c.console <> "/setup/comms/transports/tr_1"
  end

  test "B8: ground stations, New, one station and its edit go to Setup stations", c do
    assert redirected_to(get(c.conn, c.legacy <> "/comms/ground-stations")) ==
             c.console <> "/setup/stations"

    assert redirected_to(get(c.conn, c.legacy <> "/comms/ground-stations/new")) ==
             c.console <> "/setup/stations"

    assert redirected_to(get(c.conn, c.legacy <> "/comms/ground-stations/gs_1")) ==
             c.console <> "/setup/stations/gs_1"

    assert redirected_to(get(c.conn, c.legacy <> "/comms/ground-stations/gs_1/edit")) ==
             c.console <> "/setup/stations/gs_1"
  end

  test "B11: the mission applications list goes to Setup apps", c do
    assert redirected_to(get(c.conn, c.legacy <> "/applications")) == c.console <> "/setup/apps"
  end

  test "B5: a spacecraft's readiness, routing and commanding go to its Setup page", c do
    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/sc_1/readiness")) ==
             c.console <> "/setup/spacecraft/sc_1"

    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/sc_1/routing")) ==
             c.console <> "/setup/spacecraft/sc_1"

    assert redirected_to(get(c.conn, c.legacy <> "/spacecraft/sc_1/commanding")) ==
             c.console <> "/setup/spacecraft/sc_1"
  end
end
