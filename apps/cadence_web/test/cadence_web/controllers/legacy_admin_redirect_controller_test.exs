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

  test "L7: platform admin pages go to /console/admin; New and Invite to the list or the org",
       c do
    assert redirected_to(get(c.conn, "/admin")) == "/console/admin"
    assert redirected_to(get(c.conn, "/admin/runtime")) == "/console/admin/runtime"
    assert redirected_to(get(c.conn, "/admin/organizations")) == "/console/admin/organizations"

    assert redirected_to(get(c.conn, "/admin/organizations/new")) ==
             "/console/admin/organizations"

    id = c.org.organization_id

    assert redirected_to(get(c.conn, "/admin/organizations/#{id}")) ==
             "/console/admin/organizations/#{id}"

    assert redirected_to(get(c.conn, "/admin/organizations/#{id}/invite")) ==
             "/console/admin/organizations/#{id}"
  end

  test "L13: provider accounts and New go to the organization's list; one account to it", c do
    console = "/console/#{c.org.slug}/org/provider-accounts"
    assert redirected_to(get(c.conn, "/provider-accounts")) == console
    assert redirected_to(get(c.conn, "/provider-accounts/new")) == console

    assert redirected_to(get(c.conn, "/provider-accounts/provider_account_1")) ==
             console <> "/provider_account_1"
  end
end
