defmodule CadenceWeb.OrganizationHomePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    %{user: user, org: org, conn: TestFixtures.member_conn(user)}
  end

  test "home ignores foreign organization parameters and projects only the selected tenant", c do
    mission = TestFixtures.persist_mission!(c.org)
    TestFixtures.persist_spacecraft!(mission)
    foreign = TestFixtures.persist_org!()
    for _ <- 1..4, do: TestFixtures.persist_mission!(foreign)
    {:ok, view, _} = live(c.conn, "/?organization_id=#{foreign.organization_id}")
    assert has_element?(view, "#application-shell")
    assert page(view)["organization_id"] == c.org.organization_id

    assert page(view)["data"]["counts"] == %{
             "missions" => 1,
             "spacecraft" => 1,
             "active_memberships" => 1
           }

    assert [%{"id" => id}] = page(view)["data"]["recent_missions"]
    assert id == mission.mission_id
  end

  test "refresh reads new missions and leaving home clears the core page", c do
    {:ok, view, _} = live(c.conn, "/")
    assert page(view)["data"]["counts"]["missions"] == 0
    TestFixtures.persist_mission!(c.org)
    render_hook(view, "host:context", %{"path" => "/"})
    assert page(view)["data"]["counts"]["missions"] == 1
    render_hook(view, "host:context", %{"path" => "/missions"})
    assert page(view) == nil
  end

  test "anonymous and revoked-session home reads return to sign in", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), "/")
    {:ok, view, _} = live(c.conn, "/")
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => "/"})
    assert_redirect(view, "/sign-in")
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["administration_page"]
end
