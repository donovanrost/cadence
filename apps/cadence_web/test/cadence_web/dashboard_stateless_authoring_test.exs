defmodule CadenceWeb.DashboardStatelessAuthoringTest do
  # DECISIONS #76: authoring with no server-held draft; the client sends its commands.
  use CadenceWeb.ConnCase, async: false
  import CadenceWeb.DashboardAuthoringDraftTestSupport
  alias Cadence.Dashboards.{Document, StatelessAuthoring}

  setup do: authoring_draft_setup()

  @placement "placement_battery_voltage"

  defp rename(name), do: %{"event" => "rename", "input" => %{"name" => name, "description" => ""}}

  defp remove_widget(id),
    do: %{"event" => "remove_widget", "input" => %{"placement_id" => id}}

  defp ids(c), do: {c.scope, c.mission.mission_id, c.document.dashboard_id}

  test "preview stages the commands on the base version and writes nothing", c do
    {scope, mission, id} = ids(c)

    assert {:ok, preview} =
             StatelessAuthoring.preview(scope, mission, id, 1, [rename("Staged")])

    assert preview.document.name == "Staged"
    assert %{base_version: 1, current_version: 1, changes: %{"rename" => 1}} = preview
    assert preview.diff != []
    assert length(versions(c)) == 1
  end

  test "save makes the next current version; a stale base is a conflict naming the current one",
       c do
    {scope, mission, id} = ids(c)

    assert {:ok, %{version: 2, changed: true}} =
             StatelessAuthoring.save(scope, mission, id, 1, [rename("Saved")], nil)

    assert fetch(c).name == "Saved"

    assert {:error, {:conflict, 2}} =
             StatelessAuthoring.save(scope, mission, id, 1, [rename("Late")], nil)

    assert {:ok, %{version: 2, changed: false}} =
             StatelessAuthoring.save(scope, mission, id, 2, [], "nothing")
  end

  test "rebase replays onto the latest version and says why a command no longer applies", c do
    {scope, mission, id} = ids(c)

    assert {:ok, _} =
             StatelessAuthoring.save(scope, mission, id, 1, [remove_widget(@placement)], nil)

    assert {:ok, rebased} =
             StatelessAuthoring.rebase(scope, mission, id, [
               rename("Mine"),
               remove_widget(@placement)
             ])

    assert %{base_version: 2, applied: [0]} = rebased
    assert [%{index: 1, event: "remove_widget", code: :missing_placement}] = rebased.skipped
    assert rebased.document.name == "Mine"
  end

  test "the first failing command is reported by index; over the cap is its own error", c do
    {scope, mission, id} = ids(c)

    assert {:error, {:command, 1, :missing_placement, nil}} =
             StatelessAuthoring.preview(scope, mission, id, 1, [
               rename("Ok"),
               remove_widget("placement_missing")
             ])

    assert {:error, {:command, 0, :invalid_input, nil}} =
             StatelessAuthoring.preview(scope, mission, id, 1, [%{"event" => "explode"}])

    assert {:error, :too_many_commands} =
             StatelessAuthoring.save(scope, mission, id, 1, List.duplicate(rename("x"), 257), nil)
  end

  defp section(event, extra),
    do: %{
      "event" => event,
      "input" =>
        Map.merge(
          %{"title" => "Power", "description" => "", "collapsed_by_default" => false},
          extra
        )
    }

  test "new sections carry client ids, so replay is the same in preview, save and rebase", c do
    {scope, mission, id} = ids(c)
    added = section("add_section", %{"section_id" => "dash_section_a1"})
    renamed = section("update_section", %{"section_id" => "dash_section_a1", "title" => "Bus"})

    assert {:ok, preview} = StatelessAuthoring.preview(scope, mission, id, 1, [added, renamed])
    assert [%{section_id: "dash_section_a1", title: "Bus"}] = preview.document.sections

    assert {:ok, %{version: 2}} =
             StatelessAuthoring.save(scope, mission, id, 1, [added, renamed], nil)

    assert [%{section_id: "dash_section_a1"}] = fetch(c).sections

    # Without an id the replay couldn't be repeated; an id already there is refused.
    assert {:error, {:command, 0, :invalid_input, nil}} =
             StatelessAuthoring.preview(scope, mission, id, 2, [section("add_section", %{})])

    assert {:error, {:command, 0, :duplicate_id, nil}} =
             StatelessAuthoring.preview(scope, mission, id, 2, [added])

    assert {:error, {:command, 0, :invalid_input, nil}} =
             StatelessAuthoring.preview(scope, mission, id, 2, [
               section("add_section", %{"section_id" => "not-prefixed"})
             ])
  end

  test "copy keeps unsaved edits as a new dashboard; versions say who and how", c do
    {scope, mission, id} = ids(c)

    assert {:ok, copy} =
             StatelessAuthoring.copy(scope, mission, id, 1, [remove_widget(@placement)], %{
               "name" => "Copy with edits"
             })

    assert copy.dashboard_id != id
    assert copy.name == "Copy with edits"
    assert copy.placements == []
    assert Document.version(fetch(c)) == 1

    # The copy's first version names who made it (qa smoke: it read "Someone").
    assert {:ok, [%{version: 1, kind: "create", created_by: copied_by}]} =
             StatelessAuthoring.versions(scope, mission, copy.dashboard_id)

    assert copied_by == %{id: c.user.user_id, name: c.user.display_name || c.user.email}

    assert {:ok, _} = StatelessAuthoring.save(scope, mission, id, 1, [rename("Two")], nil)
    assert {:ok, _restored} = StatelessAuthoring.restore(scope, mission, id, 1, 2)

    assert {:ok, [restored, saved, created]} = StatelessAuthoring.versions(scope, mission, id)
    assert %{version: 3, kind: "revert", based_on_version: 1, current: true} = restored
    assert %{version: 2, kind: "save", current: false} = saved
    assert %{version: 1, kind: "create"} = created
    assert saved.created_by == %{id: c.user.user_id, name: c.user.display_name || c.user.email}
  end
end
