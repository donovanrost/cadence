defmodule Cadence.Control.Commanding.GroupSubmissionTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{CommandApprovalRow, CommandQueueEntryRow}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Commanding.RequestDigest
  alias Cadence.Control.Commanding.GroupSubmission

  setup do
    setup!(2)
  end

  defp submit(c, draft, opts \\ []) do
    GroupSubmission.submit(
      c.scope,
      c.mission,
      draft,
      Keyword.put_new(opts, :preflight_digest, digest(c, draft))
    )
  end

  test "a routine stack is queued per target in stack order", c do
    draft =
      draft(c.spacecraft, [
        command(c, "SET_SIGNED", %{"counter" => 1}),
        command(c, "SET_SIGNED", %{"counter" => 2})
      ])

    assert {:ok, group} = submit(c, draft)
    assert group.state == :queued
    assert group.member_count == 4

    members = GroupStore.members(c.org, c.mission, group.command_group_id)
    assert Enum.all?(members, &(&1.lifecycle_state == :queued))

    assert Enum.map(
             members,
             &{&1.group_target_index, &1.group_position}
           ) ==
             [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

    entries =
      Repo.all(
        from(q in CommandQueueEntryRow,
          where: q.mission_id == ^c.mission,
          order_by: [q.queue_lane_key, q.queue_sequence]
        )
      )

    assert length(entries) == 4

    for {_lane, lane_entries} <- Enum.group_by(entries, & &1.queue_lane_key) do
      assert Enum.map(lane_entries, & &1.queue_sequence) == [1, 2]
    end

    assert [%{kind: :submitted}] = GroupStore.events(c.mission, group.command_group_id)

    # #117 step 4b: released without a second GO, each member gets its own not_required record in
    # the submission's transaction: the submitter as actor, no separation, its own review token.
    ids = Enum.map(members, & &1.command_request_id)
    rows = Repo.all(from(a in CommandApprovalRow, where: a.command_request_id in ^ids))
    assert length(rows) == 4

    for row <- rows do
      member = Enum.find(members, &(&1.command_request_id == row.command_request_id))
      assert row.decision == "not_required"
      assert row.separated_from == []
      assert row.admin_mode == (c.scope.admin_mode? == true)
      assert row.decided_by_document["value"]["user_id"] == c.scope.user.user_id

      assert row.subject_digest ==
               RequestDigest.digest(%{member | lifecycle_state: :queued})
    end
  end

  test "a plain member (role member) submits a small routine group and it's queued (#62)", c do
    member = operator!(c, "Plain Member", :member)
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    assert {:ok, group} =
             GroupSubmission.submit(member, c.mission, draft, preflight_digest: digest(c, draft))

    assert group.state == :queued
    assert group.requested_by["user_id"] == member.user.user_id

    queued =
      CommandQueueEntryRow
      |> where([q], q.mission_id == ^c.mission)
      |> Repo.all()

    assert length(queued) == 2
  end

  test "a hazardous stack waits for a second GO and needs a log entry", c do
    draft = draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})])

    assert {:error, :log_entry_required} = submit(c, draft)

    assert {:ok, group} = submit(c, Map.put(draft, :log_entry, "Counter reset after anomaly"))
    assert group.state == :approval_pending
    assert %{"second_go_required" => true} = group.policy

    members = GroupStore.members(c.org, c.mission, group.command_group_id)
    assert Enum.all?(members, &(&1.lifecycle_state == :approval_pending))

    assert Repo.aggregate(
             from(q in CommandQueueEntryRow, where: q.mission_id == ^c.mission),
             :count
           ) == 0
  end

  test "refuses a stale preflight, a replayed operation and a NO-GO draft", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    assert {:error, :preflight_stale} = submit(c, draft, preflight_digest: "old")

    assert {:ok, group} = submit(c, draft, operation_id: "op-1")
    assert {:error, {:duplicate_operation, id}} = submit(c, draft, operation_id: "op-1")
    assert id == group.command_group_id

    bad = draft(["nobody"], [command(c, "SET_SIGNED", %{"counter" => 1})])
    assert {:error, {:preflight_no_go, %{identity_failures: [_]}}} = submit(c, bad)

    assert {:error, :title_required} = submit(c, Map.put(draft, :title, " "))
  end
end
