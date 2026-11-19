defmodule Cadence.Commanding.Groups.HaltTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{Cancellation, CommandRequestRow}
  alias Cadence.Commanding.Groups.{GroupStore, Halt}
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandGroups

  setup do
    c = setup!(2)

    draft =
      draft(c.spacecraft, [
        command(c, "SET_SIGNED", %{"counter" => 1}),
        command(c, "SET_SIGNED", %{"counter" => 2}),
        command(c, "SET_SIGNED", %{"counter" => 3})
      ])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    Map.put(c, :group, group)
  end

  defp row(c, target, position) do
    Repo.one!(
      from(r in CommandRequestRow,
        where:
          r.command_group_id == ^c.group.command_group_id and r.group_target_index == ^target and
            r.group_position == ^position
      )
    )
  end

  test "an earlier failed member of the same target halts the later ones, not other targets", c do
    assert Halt.earlier_failure(row(c, 0, 2)) == nil

    first = row(c, 0, 0)

    Repo.update_all(
      from(r in CommandRequestRow, where: r.command_request_id == ^first.command_request_id),
      set: [verification_state: "failed"]
    )

    assert Halt.earlier_failure(row(c, 0, 1)) == first.command_request_id
    assert Halt.earlier_failure(row(c, 0, 2)) == first.command_request_id
    assert Halt.earlier_failure(row(c, 1, 1)) == nil
  end

  test "a halted member counts as failed for the ones after it, and the read says why", c do
    first = row(c, 0, 0)
    second = row(c, 0, 1)

    {:ok, :ok} =
      Repo.transaction(fn ->
        Cancellation.fail_closed(
          c.org,
          c.mission,
          second.command_request_id,
          "earlier_command_failed: " <> first.command_request_id
        )
      end)

    assert Halt.earlier_failure(row(c, 0, 2)) == second.command_request_id

    {:ok, view} = CommandGroups.get(c.org, c.mission, c.group.command_group_id, nil)
    [%{members: [_, halted, _]} | _] = view.targets
    assert %{stage: :canceled, end_reason: :earlier_command_failed, caused_by: caused_by} = halted
    assert caused_by == first.command_request_id
    assert GroupStore.members(c.org, c.mission, c.group.command_group_id) |> length() == 6
  end

  test "requests outside a group are never halted", c do
    row = row(c, 0, 0)
    assert Halt.earlier_failure(%{row | command_group_id: nil}) == nil
  end
end
