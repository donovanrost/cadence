defmodule CadenceWeb.OpsSettingsPageTest do
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

    {:ok, document} =
      Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "settings-host-dashboard"
      })

    %{
      user: user,
      org: org,
      mission: mission,
      document: document,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}/settings"
    }
  end

  test "the compiled settings page binds tokens, sequences and receipts without an installation",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "dashboards.settings"
    assert original["status"] == "ready"
    fields = %{"data_visibility" => "definition_only", "expires_in_hours" => nil}
    input = command(original, 1, fields)

    assert action(view, c.path, %{original | "token" => "wrong"}, "create_share", input)["ok"] ==
             false

    result = action(view, c.path, original, "create_share", input)["snapshot"]
    assert result["status"] == "ok"
    assert result["state"]["phase"] == "review"
    assert result["receipt"]["event"] == "create_share"
    assert result["receipt"]["dashboard_id"] == c.document.dashboard_id

    [share] =
      Management.list_shares(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    assert share.created_by == c.user.user_id
    assert result["receipt"]["resource_id"] == share.dashboard_share_id

    assert action(view, c.path, original, "create_share", input)["snapshot"]["status"] ==
             "rejected"

    refresh(view, c.path)
    assert page(view)["token"] == original["token"]
    assert page(view)["data"]["phase"] == "review"
    result = action(view, c.path, original, "page_settings", %{"after_share" => nil})["snapshot"]
    assert result["state"]["sequence"] == 1
    assert result["state"]["phase"] == "review"

    assert action(view, c.path, original, "create_share", command(page(view), 2, fields))[
             "snapshot"
           ]["status"] == "rejected"

    assert action(view, c.path, original, "reload_settings", %{"sequence" => 2, "command" => %{}})[
             "snapshot"
           ]["state"]["phase"] == "ready"

    saved =
      action(
        view,
        c.path,
        original,
        "save_settings",
        command(page(view), 3, %{
          "name" => "Saved through host",
          "description" => "",
          "tags" => ["ops"],
          "defaults_json" => "{}"
        })
      )["snapshot"]

    assert saved["status"] == "ok"
    assert saved["state"]["model"]["document_version"] == 2
    assert saved["state"]["model"]["name"] == "Saved through host"
    assert saved["state"]["model"]["published_version"] == nil
  end

  test "invalid commands remain editable; stale revisions require explicit reload", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    bad = command(original, 1, %{"data_visibility" => "public", "expires_in_hours" => nil})
    invalid = action(view, c.path, original, "create_share", bad)["snapshot"]
    assert invalid["status"] == "invalid"
    assert invalid["state"]["phase"] == "ready"

    {:ok, _} =
      Documents.publish(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        1,
        []
      )

    assert action(view, c.path, original, "archive_dashboard", command(page(view), 2, %{}))[
             "snapshot"
           ]["status"] == "conflict"

    refresh(view, c.path)
    assert page(view)["data"]["phase"] == "review"

    assert action(view, c.path, original, "reload_settings", %{"sequence" => 3, "command" => %{}})[
             "snapshot"
           ]["status"] == "ok"

    assert action(view, c.path, original, "archive_dashboard", command(page(view), 4, %{}))[
             "snapshot"
           ]["state"]["model"]["lifecycle"] == "archived"
  end

  test "path identity defeats query overrides and revoked sessions cannot paginate", c do
    {:ok, view, _} = live(c.conn, c.path)
    old = page(view)
    path = c.path <> "?dashboard_id=forged&mission_id=forged"
    refresh(view, path)
    current = page(view)
    assert current["context"]["resourceId"] == c.document.dashboard_id
    assert current["context"]["missionId"] == c.mission.mission_id
    refute current["token"] == old["token"]

    assert action(view, c.path, old, "reload_settings", %{"sequence" => 1, "command" => %{}})[
             "ok"
           ] == false

    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "id" => current["id"],
      "token" => current["token"],
      "path" => path,
      "event" => "page_settings",
      "input" => %{}
    })

    assert_redirect(view, "/sign-in")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), c.path)
  end

  test "failed refresh retains the existing model but locks further writes", c do
    {:ok, view, _} = live(c.conn, c.path)
    before = page(view)

    {:ok, _} =
      Management.record_deployment(
        c.org.organization_id,
        c.mission.mission_id,
        c.document,
        "artifact",
        String.duplicate("x", 121)
      )

    refresh(view, c.path)
    current = page(view)
    assert current["status"] == "ready"
    assert current["token"] == before["token"]
    assert current["data"]["model"] == before["data"]["model"]
    assert current["data"]["phase"] == "review"

    assert action(view, c.path, current, "archive_dashboard", command(current, 1, %{}))[
             "snapshot"
           ]["status"] == "rejected"
  end

  test "the existing export remains authenticated and records the saved draft", c do
    path = String.replace_suffix(c.path, "/settings", "/export")
    conn = get(c.conn, path)
    assert conn.status == 200
    assert get_resp_header(conn, "content-disposition") != []

    [deployment] =
      Management.list_deployments(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )

    assert deployment.dashboard_version == 1
    assert deployment.created_by == c.user.user_id
    assert get(build_conn(), path).status == 302
  end

  defp command(page, sequence, fields) do
    model = page["data"]["model"]

    %{
      "sequence" => sequence,
      "command" =>
        Map.merge(
          %{
            "expected_version" => model["document_version"],
            "expected_revision" => model["revision"]
          },
          fields
        )
    }
  end

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
    Jason.decode!(Jason.encode!(reply))
  end
end
