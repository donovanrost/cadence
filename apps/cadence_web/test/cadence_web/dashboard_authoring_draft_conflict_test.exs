defmodule CadenceWeb.DashboardAuthoringDraftConflictTest do
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport
  alias Cadence.Dashboards.{AuthoringDraft, CurrentVersions, Document}
  alias Cadence.Reads.Dashboards.Editor

  setup do: authoring_draft_setup()

  test "another saved draft never silently replaces the starting version or staged content", c do
    assert {:ok, other} =
             AuthoringDraft.open(c.scope, c.mission.mission_id, c.document.dashboard_id)

    assert {:ok, mine, _} = stage(c, c.draft, "rename", %{"name" => "Mine", "description" => ""})

    assert {:ok, theirs, _} =
             stage(c, other, "rename", %{"name" => "Theirs", "description" => ""})

    assert {:ok, _, _} = AuthoringDraft.save(c.scope, theirs, control(theirs))
    assert {:error, :conflict} = AuthoringDraft.current(c.scope, mine)
    assert {:error, :conflict} = AuthoringDraft.save(c.scope, mine, control(mine))
    assert {:error, :conflict} = AuthoringDraft.discard(c.scope, mine, control(mine))

    assert {:error, :conflict} =
             stage(c, mine, "remove_widget", %{"placement_id" => "placement_battery_voltage"})

    assert {:error, :conflict} = Editor.staged(c.scope, mine)
    assert mine.document.name == "Mine"
    assert fetch(c).name == "Theirs"
    assert length(versions(c)) == 2

    assert {:ok, reopened} =
             AuthoringDraft.open(c.scope, c.mission.mission_id, c.document.dashboard_id)

    assert reopened.document.name == "Theirs"
    assert Document.version(reopened.baseline) == 2
  end

  test "rebase replays my edits onto someone else's save and reports edits that no longer apply",
       c do
    [placement] = c.document.placements

    assert {:ok, renamed, _} =
             stage(c, c.draft, "rename", %{"name" => "Mine", "description" => ""})

    assert {:ok, removed, _} =
             stage(c, renamed, "remove_widget", %{"placement_id" => placement.placement_id})

    # Their save removes the same widget and renames the description.
    assert {:ok, _} =
             CurrentVersions.save(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               %{c.document | description: "Theirs", placements: []},
               expected_version: 1
             )

    assert {:error, :conflict} = AuthoringDraft.save(c.scope, removed, control(removed))
    assert {:ok, rebased, %{skipped: ["remove_widget"]}} = AuthoringDraft.rebase(c.scope, removed)
    assert Document.version(rebased.baseline) == 2
    assert rebased.document.name == "Mine"
    assert rebased.document.description == ""
    assert {:ok, saved, _} = AuthoringDraft.save(c.scope, rebased, control(rebased))
    assert saved.document.name == "Mine"
    assert saved.document.placements == []
  end
end
