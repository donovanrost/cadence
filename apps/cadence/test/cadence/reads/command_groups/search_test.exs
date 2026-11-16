defmodule Cadence.Reads.CommandGroups.SearchTest do
  @moduledoc "U69 A5a/b/c: the Commands list searched, filtered in SQL and paged by cursor."
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandGroups

  setup do
    c = setup!(2)
    [one, two] = c.spacecraft

    routine = submit!(c, [one, two], "SET_SIGNED", %{"counter" => 1}, %{title: "Load shed"})
    single = submit!(c, [two], "SET_SIGNED", %{"counter" => 2}, %{title: "Heater trim"})

    hazardous =
      submit!(c, [one], "SET_COUNTER", %{"amount" => 1}, %{
        title: "Counter reset",
        log_entry: "Reset after the anomaly"
      })

    Map.merge(c, %{one: one, two: two, routine: routine, single: single, hazardous: hazardous})
  end

  defp submit!(c, targets, command, args, extra) do
    draft = draft(targets, [command(c, command, args)], extra)

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    group.command_group_id
  end

  defp ids(c, viewer \\ nil, opts) do
    {:ok, page} = CommandGroups.page(c.org, c.mission, viewer, opts)
    {Enum.map(page.groups, & &1.id), page.next_cursor}
  end

  test "q matches title, log entry and command; target keeps that spacecraft's groups", c do
    assert {[id], nil} = ids(c, q: "heater")
    assert id == c.single
    assert {[id], nil} = ids(c, q: "ANOMALY")
    assert id == c.hazardous
    assert {found, nil} = ids(c, q: "set_counter")
    assert c.hazardous in found
    assert {[], nil} = ids(c, q: "100%_")

    assert {found, nil} = ids(c, target: c.one)
    assert Enum.sort(found) == Enum.sort([c.routine, c.hazardous])
  end

  test "pages newest first by cursor, without repeats; a bad cursor is refused", c do
    {all, nil} = ids(c, [])
    assert length(all) == 3

    {[first], cursor} = ids(c, limit: 1)
    {[second], cursor} = ids(c, limit: 1, cursor: cursor)
    {[third], nil} = ids(c, limit: 2, cursor: cursor)
    assert [first, second, third] == all

    assert {:error, :invalid_cursor} = CommandGroups.page(c.org, c.mission, nil, cursor: "nope")
  end

  test "mine and awaiting_me are exact in SQL", c do
    other = operator!(c)
    requester = c.scope.user.user_id

    {mine, nil} = ids(c, requester, mine: true)
    assert length(mine) == 3
    assert {[], nil} = ids(c, other.user.user_id, mine: true)

    # Two-person: the hazardous group waits on someone other than its requester.
    assert {[id], nil} = ids(c, other.user.user_id, awaiting_me: true)
    assert id == c.hazardous
    assert {[], nil} = ids(c, requester, awaiting_me: true)
  end

  test "stage keeps groups where a target is at it, agreeing with progress", c do
    {queued, nil} = ids(c, stages: ["queued_for_contact"])
    assert Enum.sort(queued) == Enum.sort([c.routine, c.single])

    {:ok, page} = CommandGroups.page(c.org, c.mission, nil, stages: ["queued_for_contact"])
    assert Enum.all?(page.groups, &Map.has_key?(&1.progress, :queued_for_contact))

    assert {[], nil} = ids(c, stages: ["release_failed", "verify_failed", "indeterminate"])
    assert {[], nil} = ids(c, stages: ["in_flight"])
  end
end
