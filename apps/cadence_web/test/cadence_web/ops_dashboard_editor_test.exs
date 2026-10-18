defmodule CadenceWeb.OpsDashboardEditorTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardPageTestSupport
  alias Cadence.Dashboards.{AuthoringWidget, Documents}
  alias CadenceWeb.TestFixtures

  setup do: dashboard_page_setup()

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
      save(c, %{c.document | name: "Theirs"}, 1)

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

    test "a save records the author's note and opt-in time and spacecraft defaults", c do
      craft = TestFixtures.persist_spacecraft!(c.mission)
      path = c.edit <> "?from=now-6h&to=now&spacecraft=#{craft.spacecraft_id}"
      {:ok, view, _} = live(c.conn, path)
      opened = page(view)
      stage(view, path, opened, "rename", 1, %{"name" => "Noted", "description" => ""})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      staged = page(view)

      assert [%{"label" => "Renamed dashboard", "detail" => detail} | _] =
               staged["data"]["edit"]["changes"]

      assert detail =~ "→ Noted"

      command =
        Map.merge(control(staged), %{
          "message" => "  Pass review layout  ",
          "defaults" => %{"time" => true, "scope" => true}
        })

      action(view, path, staged, "save", 2, command)
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      saved = fetch(c)
      assert saved.name == "Noted"
      assert %{"mode" => "live", "window_seconds" => 21_600} = saved.defaults["time"]
      assert saved.defaults["scope"]["spacecraft_id"] == craft.spacecraft_id
      assert List.last(versions(c)).change_summary == "Pass review layout"
      assert page(view)["data"]["mode"] == "edit"
      refute page(view)["data"]["edit"]["dirty"]
    end

    test "save as copy creates a new current dashboard from the staged candidate", c do
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)
      stage(view, c.edit, opened, "rename", 1, %{"name" => "Staged", "description" => ""})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      action(view, c.edit, page(view), "save_as_copy", 2, %{"name" => "Pass copy"})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok", result: %{dashboard_id: copy_id}}})

      assert {:ok, copy} =
               Documents.fetch_published(c.org.organization_id, c.mission.mission_id, copy_id)

      assert copy.name == "Pass copy"
      assert fetch(c).name == c.document.name
    end

    test "someone else's save is surfaced while editing; rebase replays my edits on theirs", c do
      {:ok, view, _} = live(c.conn, c.edit)
      opened = page(view)

      stage(view, c.edit, opened, "add_section", 1, %{
        "title" => "Mine",
        "description" => "",
        "collapsed_by_default" => false
      })

      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      save(c, %{c.document | name: "Theirs"}, 1)
      # The version-changed broadcast re-prepares the edit page (no tick in edit mode).
      send(view.pid, {:dashboard_live_flush, page(view)["token"]})
      conflicted = page(view)
      assert conflicted["data"]["edit"]["conflict"]
      assert conflicted["data"]["saved"]["version"] == 2

      action(view, c.edit, conflicted, "rebase", 2, %{})
      assert_reply(view, %{ok: true, snapshot: %{status: "ok", result: %{skipped: []}}})
      rebased = page(view)
      refute rebased["data"]["edit"]["conflict"]
      assert rebased["data"]["edit"]["document_version"] == 2
      assert rebased["data"]["snapshot"]["name"] == "Theirs"
      assert Enum.any?(rebased["data"]["snapshot"]["sections"], &(&1["title"] == "Mine"))

      action(view, c.edit, rebased, "save", 3, control(rebased))
      assert_reply(view, %{ok: true, snapshot: %{status: "ok"}})
      saved = fetch(c)
      assert saved.name == "Theirs"
      assert Enum.any?(saved.sections, &(&1.title == "Mine"))
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
end
