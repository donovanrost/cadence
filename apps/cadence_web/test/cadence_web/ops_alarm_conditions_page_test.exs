defmodule CadenceWeb.OpsAlarmConditionsPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission,
      path: "/missions/#{mission.mission_id}/ops/alarms"
    }
  end

  test "host composes the owner and refreshes only captured selectors without effects", c do
    path = c.path <> "?state=active&query=voltage&page=2"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["id"] == "limits.alarm-conditions"
    assert original["status"] == "ready"
    assert original["data"]["query"]["state"] == "active"
    assert original["data"]["query"]["page"] == 2
    assert original["data"]["states"]["page"] == 1
    refreshed = read(view, path, original)["snapshot"]
    assert refreshed["token"] == original["token"]
    assert refreshed["data"]["query"] == original["data"]["query"]
    assert page(view) == original

    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"],
      "event" => "acknowledge",
      "input" => %{}
    })

    assert_reply(view, %{ok: false})
  end

  test "wrong identities, tokens, paths and injected selectors cannot refresh", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)

    for changes <- [
          %{"id" => "unknown"},
          %{"token" => Ecto.UUID.generate()},
          %{"path" => c.path <> "?page=2"},
          %{"input" => %{"state" => "nominal"}},
          %{"mission_id" => "foreign"}
        ] do
      request =
        Map.merge(
          %{"id" => original["id"], "token" => original["token"], "path" => c.path},
          changes
        )

      render_hook(view, "host:ops-page:read", request)
      assert_reply(view, %{ok: false})
    end

    render_hook(view, "host:context", %{"path" => c.path <> "?state=active"})
    assert_reply(view, %{ok: true})
    assert read(view, c.path, original)["ok"] == false
  end

  test "invalid filters retain host navigation and revoked sessions cannot recover", c do
    {:ok, invalid, _} = live(c.conn, c.path <> "?state=unknown")
    assert has_element?(invalid, "#application-shell")
    assert page(invalid)["status"] == "unavailable"
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page:read", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"]
    })

    assert_redirect(view, "/sign-in")
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, original) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
