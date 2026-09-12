defmodule CadenceWeb.OpsWorkspacePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Dashboards.{DocumentCodec, Documents}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/workspace/viewer-producer-render-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "viewer-" <> Ecto.UUID.generate(),
        placements: [],
        sections: []
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    path = "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}"

    %{
      org: org,
      mission: mission,
      document: document,
      conn: TestFixtures.member_conn(user),
      path: path
    }
  end

  test "authenticated viewer pins published identity, refreshes and renders its real DTO", c do
    {:ok, view, _} = live(c.conn, c.path)
    assert page(view)["status"] == "ready"
    prerequisite = page(view)
    assert prerequisite["data"]["state"] == "publication_required"
    assert prerequisite["data"]["author"] == true
    refute Map.has_key?(prerequisite["data"], "name")
    publish(c)
    refresh(view, c.path)
    first = page(view)
    assert first["status"] == "ready"
    assert first["id"] == "dashboards.workspace"
    assert first["context"]["resourceId"] == c.document.dashboard_id
    assert first["data"]["document_mode"] == "published"
    assert first["data"]["document_version"] == 1

    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | name: "Private draft"},
               expected_version: 1
             )

    refresh(view, c.path)
    assert page(view)["token"] == first["token"]
    assert page(view)["data"]["name"] == c.document.name

    node = System.find_executable("node") || flunk("Node is required for the viewer contract")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!([prerequisite, page(view)])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "URL runtime is admitted, changes page identity and never reuses unavailable data", c do
    publish(c)
    {:ok, view, _} = live(c.conn, c.path)
    token = page(view)["token"]

    path =
      c.path <>
        "?time_mode=range&time_axis=receipt_time&from=2026-09-07T00%3A00%3A00Z&to=2026-09-07T01%3A00%3A00Z&realm=rehearsal&selection_view=as_recorded&limit_mode=current"

    refresh(view, path)
    assert page(view)["status"] == "ready"
    refute page(view)["token"] == token
    context = page(view)["data"]["context"]
    assert context["time_mode"] == "range"
    assert context["time_axis"] == "receipt_time"
    assert context["from"] == "2026-09-07T00:00:00Z"
    assert context["realm"] == "rehearsal"
    assert context["data_view"] == "as_recorded"
    assert context["limit_mode"] == "current"

    refresh(view, c.path <> "?time_mode=range&from=bad")
    assert page(view)["status"] == "unavailable"
    refute Map.has_key?(page(view), "data")
    refresh(view, c.path)
    assert page(view)["status"] == "ready"
  end

  test "path identity wins forged query identity and missing or foreign dashboards remain unavailable",
       c do
    publish(c)
    {:ok, view, _} = live(c.conn, c.path <> "?dashboard_id=forged&mission_id=forged")
    assert page(view)["status"] == "ready"
    assert page(view)["data"]["dashboard_id"] == c.document.dashboard_id
    assert page(view)["data"]["mission_id"] == c.mission.mission_id

    other = TestFixtures.persist_mission!(c.org)
    refresh(view, "/missions/#{other.mission_id}/ops/dashboards/#{c.document.dashboard_id}")
    assert page(view)["status"] == "unavailable"
    refresh(view, c.path <> "-missing")
    assert page(view)["status"] == "unavailable"
    refresh(view, "/missions/#{c.mission.mission_id}/ops/dashboards")
    assert page(view)["id"] == "dashboards.directory"
  end

  test "viewer refresh rechecks the authenticated session", c do
    publish(c)
    {:ok, view, _} = live(c.conn, c.path)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => c.path})
    assert_redirect(view, "/sign-in")
  end

  defp publish(c),
    do:
      Documents.publish(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id, 1,
        expected_version: 1
      )

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end
end
