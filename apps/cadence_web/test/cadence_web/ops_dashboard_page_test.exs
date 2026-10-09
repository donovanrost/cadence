defmodule CadenceWeb.OpsDashboardPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Dashboards.{AuthoringWidget, DocumentCodec, Documents}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/dashboard/producer-render-check.mjs",
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
        dashboard_id: "dashboard-" <> Ecto.UUID.generate(),
        metadata: %{secret: "private-authoring-metadata"}
    }

    {:ok, document} = Documents.persist(org.organization_id, document)
    path = "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}"

    %{
      org: org,
      mission: mission,
      user: user,
      document: document,
      conn: TestFixtures.member_conn(user),
      path: path,
      edit: path <> "/edit"
    }
  end

  describe "viewer" do
    test "authors see the unpublished draft, then the published version; both render in Vue", c do
      {:ok, view, _} = live(c.conn, c.path)
      draft = page(view)
      assert draft["id"] == "dashboards.workspace"
      assert draft["status"] == "ready"
      assert draft["data"]["mode"] == "view"
      assert draft["data"]["author"] == true
      assert draft["data"]["snapshot"]["document_mode"] == "draft"
      assert draft["data"]["publication"]["state"] == "unpublished"
      refute Jason.encode!(draft) =~ "private-authoring-metadata"

      publish(c, 1)
      refresh(view, c.path)
      published = page(view)
      assert published["data"]["publication"]["state"] == "published"
      assert published["data"]["publication"]["published_version"] == 1

      update(c, %{c.document | name: "Next draft"}, 1)
      refresh(view, c.path)
      ahead = page(view)
      assert ahead["data"]["snapshot"]["name"] == "Next draft"
      assert ahead["data"]["publication"]["state"] == "draft_ahead"

      assert_renders([draft, published, ahead])
    end

    test "live views declare refresh delivery and re-resolve on ticks and invalidations", c do
      {:ok, view, _} = live(c.conn, c.path)
      first = page(view)
      assert %{"active" => true, "refresh_ms" => ms} = first["data"]["live"]
      assert ms in 1000..60_000

      send(view.pid, {:dashboard_live_tick, first["token"]})
      later = page(view)
      assert later["token"] == first["token"]
      assert later["data"]["resolved_at"] > first["data"]["resolved_at"]

      send(view.pid, {:dashboard_live_tick, Ecto.UUID.generate()})
      assert page(view)["data"]["resolved_at"] == later["data"]["resolved_at"]

      refresh(view, c.path <> "?from=2026-09-07T00:00:00Z&to=2026-09-07T01:00:00Z")
      assert page(view)["data"]["live"]["active"] == false
    end

    test "Grafana ranges and the spacecraft scope are admitted; foreign spacecraft are not", c do
      craft = TestFixtures.persist_spacecraft!(c.mission)

      {:ok, view, _} =
        live(c.conn, c.path <> "?from=now-6h&to=now&spacecraft=#{craft.spacecraft_id}")

      data = page(view)["data"]
      assert data["snapshot"]["context"]["time_mode"] == "live"
      assert data["snapshot"]["context"]["window_seconds"] == 21_600
      assert data["snapshot"]["context"]["scope_kind"] == "spacecraft"
      assert data["snapshot"]["context"]["scope_ids"] == [craft.spacecraft_id]
      assert Enum.any?(data["scope_options"], &(&1["id"] == craft.spacecraft_id))

      other = TestFixtures.persist_mission!(c.org)
      foreign = TestFixtures.persist_spacecraft!(other)
      refresh(view, c.path <> "?spacecraft=#{foreign.spacecraft_id}")
      assert page(view)["status"] == "unavailable"
      refresh(view, c.path <> "?from=now-30d&to=now")
      assert page(view)["status"] == "unavailable"
      refresh(view, c.path <> "?time_mode=range&from=bad")
      assert page(view)["status"] == "unavailable"
      refresh(view, c.path)
      assert page(view)["status"] == "ready"
    end

    test "path identity wins forged query identity; foreign missions stay unavailable", c do
      {:ok, view, _} = live(c.conn, c.path <> "?dashboard_id=forged&mission_id=forged")
      assert page(view)["data"]["snapshot"]["dashboard_id"] == c.document.dashboard_id

      other = TestFixtures.persist_mission!(c.org)
      refresh(view, "/missions/#{other.mission_id}/ops/dashboards/#{c.document.dashboard_id}")
      assert page(view)["status"] == "unavailable"
    end

    test "publishing from the viewer requires the observed latest version", c do
      {:ok, view, _} = live(c.conn, c.path)
      first = page(view)
      action(view, c.path, first, "publish", 1, %{"version" => 2})
      assert_reply(view, %{ok: true, snapshot: %{status: "conflict"}})
      action(view, c.path, first, "publish", 2, %{"version" => 1})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      assert page(view)["data"]["publication"]["state"] == "published"
      action(view, c.path, first, "publish", 2, %{"version" => 1})
      assert_reply(view, %{ok: true, snapshot: %{status: "rejected"}})
    end

    test "refresh rechecks the authenticated session", c do
      {:ok, view, _} = live(c.conn, c.path)
      :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
      render_hook(view, "host:context", %{"path" => c.path})
      assert_redirect(view, "/sign-in")
    end
  end

  describe "editor" do
    test "staging resolves the candidate in place and persists exactly once on save", c do
      [first] = c.document.placements
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)
      assert opened["data"]["mode"] == "edit"
      assert opened["data"]["live"]["active"] == false
      assert opened["data"]["edit"]["document_version"] == 1
      refute opened["data"]["edit"]["dirty"]

      layouts = [%{"placement_id" => first.placement_id, "x" => 4, "y" => 0, "w" => 4, "h" => 3}]
      stage(view, c.edit, opened, "layout", 1, %{"layouts" => layouts})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok", page: %{data: %{sequence: 1}}}})
      staged = page(view)
      assert staged["data"]["edit"]["dirty"]
      assert [%{"layout" => %{"x" => 4}}] = staged["data"]["snapshot"]["placements"]
      assert fetch(c).placements == c.document.placements

      action(view, c.edit, staged, "save", 2, control(staged))
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      saved = page(view)
      refute saved["data"]["edit"]["dirty"]
      assert saved["data"]["edit"]["document_version"] == 2
      assert [%{layout: %{x: 4}}] = fetch(c).placements
      assert length(versions(c)) == 2

      assert_renders([opened, staged, saved])
    end

    test "invalid input keeps the draft editable; discard restores the saved document", c do
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)
      stage(view, c.edit, opened, "rename", 1, %{"name" => "", "description" => ""})
      assert_reply(view, %{ok: true, snapshot: %{status: "invalid"}})
      stage(view, c.edit, page(view), "rename", 2, %{"name" => "Candidate", "description" => ""})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      assert page(view)["data"]["snapshot"]["name"] == "Candidate"
      action(view, c.edit, page(view), "discard", 3, control(page(view)))
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      assert page(view)["data"]["snapshot"]["name"] == c.document.name
      refute page(view)["data"]["edit"]["dirty"]
      assert length(versions(c)) == 1
    end

    test "a concurrent save is reported, cannot be saved over, and discard adopts it", c do
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)
      stage(view, c.edit, opened, "rename", 1, %{"name" => "Mine", "description" => ""})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      update(c, %{c.document | name: "Theirs"}, 1)

      action(view, c.edit, page(view), "save", 2, control(page(view)))
      assert_reply(view, %{ok: true, snapshot: %{status: "conflict"}})
      conflicted = page(view)
      assert conflicted["status"] == "ready"
      assert conflicted["data"]["edit"]["conflict"]
      assert fetch(c).name == "Theirs"

      action(view, c.edit, conflicted, "discard", 3, control(conflicted))
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      adopted = page(view)
      refute adopted["data"]["edit"]["conflict"]
      assert adopted["data"]["edit"]["document_version"] == 2
      assert adopted["data"]["snapshot"]["name"] == "Theirs"
    end

    test "commands bind the page token and sequence; foreign tokens author nothing", c do
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)
      command = %{"name" => "Forged", "description" => ""}
      request = request(c.edit, opened, "rename", 1, Map.merge(command, control(opened)))
      render_hook(view, "host:ops-page", %{request | "token" => Ecto.UUID.generate()})
      assert_reply(view, %{ok: false})
      stage(view, c.edit, opened, "rename", 5, command)
      assert_reply(view, %{ok: true, snapshot: %{status: "rejected"}})
      refute page(view)["data"]["edit"]["dirty"]
      refresh(view, c.path)
      render_hook(view, "host:ops-page", request)
      assert_reply(view, %{ok: false})
    end

    test "observable search is scoped, side-effect free and needs edit mode", c do
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)

      fields =
        Map.merge(AuthoringWidget.defaults(), %{
          "type" => "time_series",
          "binding_source" => "operational_observables",
          "mode" => "scope",
          "scope_kind" => "spacecraft",
          "scope_id" => "craft"
        })

      render_hook(view, "host:ops-page", search(c.edit, opened, fields, "downlink"))

      assert_reply(view, %{
        ok: true,
        snapshot: %{
          status: "ok",
          choices: %{options: [%{value: "comms.transport.downlink_bitrate"}]}
        }
      })

      assert page(view) == opened
      refresh(view, c.path)
      render_hook(view, "host:ops-page", search(c.path, page(view), fields, "downlink"))
      assert_reply(view, %{ok: true, snapshot: %{status: "unavailable"}})
    end
  end

  defp assert_renders(pages) do
    node = System.find_executable("node") || flunk("Node is required for the page contract")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!(pages)], stderr_to_stdout: true)

    assert status == 0, output
  end

  defp publish(c, version),
    do:
      Documents.publish(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        version,
        expected_version: version
      )

  defp update(c, document, version) do
    assert {:ok, _} =
             Documents.update(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               document,
               expected_version: version
             )
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp control(page),
    do: %{
      "expected_version" => page["data"]["edit"]["document_version"],
      "expected_revision" => page["data"]["edit"]["revision"]
    }

  defp stage(view, path, page, event, sequence, command),
    do: action(view, path, page, event, sequence, Map.merge(command, control(page)))

  defp action(view, path, page, event, sequence, command),
    do: render_hook(view, "host:ops-page", request(path, page, event, sequence, command))

  defp request(path, page, event, sequence, command) do
    %{
      "path" => path,
      "id" => "dashboards.workspace",
      "token" => page["token"],
      "event" => event,
      "input" => %{"sequence" => sequence, "command" => command}
    }
  end

  defp search(path, page, fields, query) do
    %{
      "path" => path,
      "id" => "dashboards.workspace",
      "token" => page["token"],
      "event" => "search_observables",
      "input" => %{
        "query" => query,
        "fields" => fields,
        "expected_version" => get_in(page, ["data", "edit", "document_version"]) || 1,
        "expected_revision" => get_in(page, ["data", "edit", "revision"]) || 0
      }
    }
  end

  defp fetch(c) do
    {:ok, document} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    document
  end

  defp versions(c),
    do:
      Documents.list_versions(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )
end
