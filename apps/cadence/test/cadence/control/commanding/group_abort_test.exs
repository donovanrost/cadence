defmodule Cadence.Control.Commanding.GroupAbortTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{Cancellation, CommandQueueEntryRow}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupAbort, GroupSubmission}

  setup do
    c = setup!(2)

    draft =
      draft(c.spacecraft, [
        command(c, "SET_SIGNED", %{"counter" => 1}),
        command(c, "SET_SIGNED", %{"counter" => 2})
      ])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    Map.merge(c, %{group: group, operator: operator!(c)})
  end

  defp members(c), do: GroupStore.members(c.org, c.mission, c.group.command_group_id)

  defp entry_states(c),
    do:
      Repo.all(
        from(q in CommandQueueEntryRow,
          where: q.mission_id == ^c.mission,
          select: q.lifecycle_state
        )
      )

  test "any operator aborts a queued group; every pending member is canceled", c do
    assert {:error, :reason_required} =
             GroupAbort.abort(c.operator, c.mission, c.group.command_group_id, " ")

    assert {:ok, group} =
             GroupAbort.abort(c.operator, c.mission, c.group.command_group_id, "Wrong targets")

    assert group.state == :aborted
    assert group.abort_reason == "Wrong targets"
    assert group.abort_result == %{"canceled" => 4, "already_started" => []}

    assert Enum.all?(members(c), &(&1.lifecycle_state == :canceled))

    assert Enum.all?(
             members(c),
             &(&1.metadata["cancellation"]["reason"] == "aborted: Wrong targets")
           )

    assert Enum.uniq(entry_states(c)) == ["canceled"]
    assert Enum.any?(GroupStore.events(c.mission, group.command_group_id), &(&1.kind == :aborted))

    assert {:error, :command_group_not_abortable} =
             GroupAbort.abort(c.operator, c.mission, c.group.command_group_id, "again")
  end

  test "a member already releasing keeps running and is reported", c do
    [first | _] = members(c)

    Repo.update_all(
      from(q in CommandQueueEntryRow, where: q.command_request_id == ^first.command_request_id),
      set: [lifecycle_state: "release_pending"]
    )

    assert {:ok, group} =
             GroupAbort.abort(c.operator, c.mission, c.group.command_group_id, "Stop")

    assert group.abort_result == %{
             "canceled" => 3,
             "already_started" => [first.command_request_id]
           }
  end

  test "cancel a single request unless it has started", c do
    [first, second | _] = members(c)

    assert {:ok, %{state: :canceled}} =
             GroupAbort.cancel_request(
               c.operator,
               c.mission,
               first.command_request_id,
               "Not needed"
             )

    assert Enum.any?(
             GroupStore.events(c.mission, c.group.command_group_id),
             &(&1.kind == :member_canceled)
           )

    Repo.update_all(
      from(q in CommandQueueEntryRow, where: q.command_request_id == ^second.command_request_id),
      set: [lifecycle_state: "released"]
    )

    assert {:error, :command_request_already_started} =
             GroupAbort.cancel_request(
               c.operator,
               c.mission,
               second.command_request_id,
               "Too late"
             )

    assert {:error, :command_request_not_found} =
             GroupAbort.cancel_request(c.operator, c.mission, "nope", "x")
  end

  test "failing a lane head closed cancels it with release_basis_changed", c do
    [first | _] = members(c)

    assert :ok =
             Repo.transaction(fn ->
               Cancellation.fail_closed(
                 c.org,
                 c.mission,
                 first.command_request_id,
                 "release_basis_changed"
               )
             end)
             |> elem(1)

    [failed | _] = members(c)
    assert failed.lifecycle_state == :canceled
    assert failed.metadata["cancellation"]["reason"] == "release_basis_changed"
  end
end
