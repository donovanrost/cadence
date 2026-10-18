defmodule CadenceWeb.OpsLandingPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, org: org, mission: mission, conn: TestFixtures.member_conn(user)}
  end

  test "canonical entry uses authenticated mission identity and clears its model when navigating away",
       c do
    foreign_org = TestFixtures.persist_org!()
    foreign = TestFixtures.persist_mission!(foreign_org)

    {:ok, view, _} =
      live(
        c.conn,
        path(c) <>
          "?mission_id=#{foreign.mission_id}&organization_id=#{foreign_org.organization_id}"
      )

    assert has_element?(view, "#application-shell")

    assert page(view)["context"] == %{
             "organization_id" => c.org.organization_id,
             "mission_id" => c.mission.mission_id
           }

    assert page(view)["can_administer"] == false
    render_hook(view, "host:context", %{"path" => path(c) <> "/dashboards"})
    assert page(view) == nil
    render_hook(view, "host:context", %{"path" => path(c)})
    assert page(view)["context"]["mission_id"] == c.mission.mission_id
  end

  test "foreign mission entry and client-side navigation are rejected before producing the model",
       c do
    foreign_org = TestFixtures.persist_org!()
    foreign = TestFixtures.persist_mission!(foreign_org)
    destination = "/missions/#{foreign.mission_id}/ops"
    assert {:error, {:redirect, %{to: "/missions"}}} = live(c.conn, destination)
    {:ok, view, _} = live(c.conn, path(c))

    assert {:error, {:redirect, %{to: "/missions"}}} =
             render_hook(view, "host:context", %{"path" => destination})
  end

  test "anonymous entry and revoked refresh do not expose navigation", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path(c))
    {:ok, view, _} = live(c.conn, path(c))
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => path(c)})
    assert_redirect(view, "/sign-in")
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_landing_page"]

  defp path(c), do: "/missions/#{c.mission.mission_id}/ops"
end
