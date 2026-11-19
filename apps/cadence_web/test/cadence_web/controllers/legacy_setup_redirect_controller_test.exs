defmodule CadenceWeb.LegacySetupRedirectControllerTest do
  @moduledoc "Legacy mission Ops pages moved to the console's Setup (DECISIONS #79)."
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
      legacy: "/missions/#{mission.mission_id}/ops",
      other: "/missions/#{other.mission_id}/ops",
      console: "/console/#{org.slug}/#{mission.slug}/setup"
    }
  end

  test "L1-L3: requirements, templates and the fleet policy go to contact planning", c do
    assert redirected_to(get(c.conn, c.legacy <> "/requirements")) ==
             c.console <> "/contact-planning"

    assert redirected_to(get(c.conn, c.legacy <> "/requirements/new")) ==
             c.console <> "/contact-planning"

    assert redirected_to(get(c.conn, c.legacy <> "/requirements/contact_requirement_1")) ==
             c.console <> "/contact-planning/requirements/contact_requirement_1"

    assert redirected_to(get(c.conn, c.legacy <> "/requirement-templates")) ==
             c.console <> "/contact-planning"

    assert redirected_to(get(c.conn, c.legacy <> "/planning/policy")) ==
             c.console <> "/contact-planning/policy"
  end

  test "L11: data sources and registration go to the list; one source and its settings to it",
       c do
    assert redirected_to(get(c.conn, c.legacy <> "/data-sources")) == c.console <> "/data-sources"

    assert redirected_to(get(c.conn, c.legacy <> "/data-sources/registration/new")) ==
             c.console <> "/data-sources"

    assert redirected_to(get(c.conn, c.legacy <> "/data-sources/src_1")) ==
             c.console <> "/data-sources/src_1"

    assert redirected_to(get(c.conn, c.legacy <> "/data-sources/src_1/settings")) ==
             c.console <> "/data-sources/src_1"
  end

  test "L12: mission providers and New go to Setup's providers; one provider to it", c do
    comms = String.replace_suffix(c.legacy, "/ops", "/comms")

    assert redirected_to(get(c.conn, comms <> "/providers")) ==
             c.console <> "/stations/providers"

    assert redirected_to(get(c.conn, comms <> "/providers/new")) ==
             c.console <> "/stations/providers"

    assert redirected_to(get(c.conn, comms <> "/providers/provider_1")) ==
             c.console <> "/stations/providers/provider_1"
  end

  test "another organization's mission falls back to the console's home", c do
    assert redirected_to(get(c.conn, c.other <> "/requirements")) == "/console"
  end
end
