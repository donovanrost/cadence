defmodule CadenceWeb.OpsPlaylistPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Dashboards.{DocumentCodec, Documents, Management}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    base = DocumentCodec.load!(@fixture)

    {:ok, dashboard} =
      Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "playlist-dashboard"
      })

    %{
      conn: TestFixtures.member_conn(user),
      user: user,
      org: org,
      mission: mission,
      dashboard: dashboard,
      path: "/missions/#{mission.mission_id}/ops/dashboards/playlists"
    }
  end

  test "creation consumes one instance, lookup does not, and refresh cannot unlock it", c do
    {:ok, view, _} = live(c.conn, c.path)
    current = page(view)

    assert action(view, c.path, current, "search_dashboards", %{"q" => ""})["snapshot"]["status"] ==
             "ok"

    input = %{"sequence" => 1, "fields" => fields(c)}

    assert action(view, c.path, %{current | "token" => "wrong"}, "create_playlist", input)["ok"] ==
             false

    result = action(view, c.path, current, "create_playlist", input)["snapshot"]
    assert result["status"] == "ok"
    assert result["phase"] == "review"

    assert action(view, c.path, current, "create_playlist", input)["snapshot"]["status"] ==
             "rejected"

    refresh(view, c.path)
    assert page(view)["data"]["phase"] == "review"

    assert action(view, c.path, current, "create_playlist", %{input | "sequence" => 2})[
             "snapshot"
           ]["status"] == "rejected"

    assert action(view, c.path, current, "reload_playlists", %{"sequence" => 2, "fields" => %{}})[
             "snapshot"
           ]["phase"] == "ready"

    [saved] = Management.list_playlists(c.org.organization_id, c.mission.mission_id)
    assert saved.created_by == c.user.user_id
    refresh(view, c.path <> "?q=Flight")
    refute page(view)["token"] == current["token"]

    assert action(view, c.path, current, "create_playlist", %{input | "sequence" => 3})["ok"] ==
             false

    path =
      c.path <> "/#{saved.dashboard_playlist_id}/present?index=0&playing=0&playlist_id=forged"

    refresh(view, path)
    assert page(view)["context"]["resourceId"] == saved.dashboard_playlist_id
    assert page(view)["data"]["current"]["id"] == c.dashboard.dashboard_id
    assert page(view)["data"]["current"]["snapshot"] == nil
    refresh(view, c.path <> "/#{saved.dashboard_playlist_id}/present?index=1")
    assert page(view)["status"] == "unavailable"
  end

  test "known invalid creation retains editing and revoked sessions cannot search", c do
    {:ok, view, _} = live(c.conn, c.path)
    current = page(view)

    result =
      action(view, c.path, current, "create_playlist", %{
        "sequence" => 1,
        "fields" => %{fields(c) | "dashboard_ids" => ["foreign"]}
      })["snapshot"]

    assert result["status"] == "invalid"
    assert result["phase"] == "ready"
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "id" => current["id"],
      "token" => current["token"],
      "path" => c.path,
      "event" => "search_dashboards",
      "input" => %{}
    })

    assert_redirect(view, "/sign-in")
  end

  test "both playlist URLs retain authentication admission", c do
    for path <- [c.path, c.path <> "/missing/present"] do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path)
    end
  end

  defp fields(c),
    do: %{
      "name" => "Flight queue",
      "description" => "",
      "dashboard_ids" => [c.dashboard.dashboard_id],
      "dwell_seconds" => 30,
      "wallboard_mode" => false
    }

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => path,
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
