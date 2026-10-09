defmodule CadenceWeb.OpsDashboardPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardPageTestSupport
  alias CadenceWeb.TestFixtures

  setup do: dashboard_page_setup()

  describe "viewer" do
    test "every save is the current version everyone sees, and it renders in Vue", c do
      {:ok, view, _} = live(c.conn, c.path)
      first = page(view)
      assert first["id"] == "dashboards.workspace"
      assert first["status"] == "ready"
      assert first["data"]["mode"] == "view"
      assert first["data"]["author"] == true
      assert first["data"]["saved"]["version"] == 1
      refute Map.has_key?(first["data"], "publication")
      refute Jason.encode!(first) =~ "private-authoring-metadata"

      save(c, %{c.document | name: "Next version"}, 1)
      refresh(view, c.path)
      second = page(view)
      assert second["data"]["snapshot"]["name"] == "Next version"
      assert second["data"]["snapshot"]["document_mode"] == "published"
      assert second["data"]["saved"]["version"] == 2

      assert_renders([first, second])
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

    test "versions are listed, compared and restored as a new current version", c do
      save(c, %{c.document | name: "Renamed"}, 1)
      {:ok, view, _} = live(c.conn, c.path)
      first = page(view)

      query(view, c.path, first, "versions", %{})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok", versions: versions}})
      assert [%{version: 2, current: true}, %{version: 1, current: false}] = versions.versions

      query(view, c.path, first, "compare", %{"from" => 1, "to" => 2})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok", comparison: comparison}})
      assert [%{label: "Renamed dashboard"}] = comparison.changes
      refute comparison.to_json =~ "private-authoring-metadata"

      action(view, c.path, first, "restore", 1, %{"version" => 1, "expected_version" => 1})
      assert_reply(view, %{ok: true, snapshot: %{status: "conflict"}})
      action(view, c.path, first, "restore", 2, %{"version" => 1, "expected_version" => 2})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok", result: %{version: 3}}})
      assert page(view)["data"]["saved"]["version"] == 3
      assert page(view)["data"]["snapshot"]["name"] == c.document.name
      assert fetch(c).name == c.document.name
    end

    test "refresh rechecks the authenticated session", c do
      {:ok, view, _} = live(c.conn, c.path)
      :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
      render_hook(view, "host:context", %{"path" => c.path})
      assert_redirect(view, "/sign-in")
    end
  end
end
