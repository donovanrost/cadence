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

  test "another organization's mission falls back to the console's home", c do
    assert redirected_to(get(c.conn, c.other <> "/requirements")) == "/console"
  end
end
