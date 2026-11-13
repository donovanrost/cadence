defmodule CadenceWeb.LegacyAdminRedirectControllerTest do
  @moduledoc "Legacy organization and platform pages moved to the console (DECISIONS #79)."
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    %{conn: TestFixtures.member_conn(user), org: org}
  end

  test "L4: the missions list and New mission go to the organization's console pages", c do
    assert redirected_to(get(c.conn, "/missions")) == "/console/#{c.org.slug}/org/missions"

    assert redirected_to(get(c.conn, "/missions/new")) ==
             "/console/#{c.org.slug}/org/missions/new"
  end
end
