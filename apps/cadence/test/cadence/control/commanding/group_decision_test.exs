defmodule Cadence.Control.Commanding.GroupDecisionTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{CommandApprovalRow, CommandQueueEntryRow}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}

  setup do
    c = setup!(3)

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{
        log_entry: "Reset counters"
      })

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    Map.merge(c, %{group: group, approver: operator!(c)})
  end

  defp decide(c, scope, decision),
    do: GroupDecision.decide(scope, c.mission, c.group.command_group_id, decision)

  defp members(c), do: GroupStore.members(c.org, c.mission, c.group.command_group_id)

  defp queue_count(c),
    do: Repo.aggregate(from(q in CommandQueueEntryRow, where: q.mission_id == ^c.mission), :count)

  test "GO approves and enqueues every member with one approval row each", c do
    assert {:ok, group} =
             decide(c, c.approver, %{
               kind: :go,
               expected_review: GroupDecision.review_token(c.group)
             })

    assert group.state == :queued
    assert group.decided_by["user_id"] == c.approver.user.user_id

    assert Enum.all?(members(c), &(&1.lifecycle_state == :queued))
    assert queue_count(c) == 3

    approvals = Repo.all(from(a in CommandApprovalRow, where: a.mission_id == ^c.mission))
    assert length(approvals) == 3
    assert Enum.all?(approvals, &(&1.decision == "approved"))

    assert Enum.any?(
             GroupStore.events(c.mission, group.command_group_id),
             &(&1.kind == :approved)
           )
  end

  test "GO excluding a target rejects only its members", c do
    assert {:ok, _group} =
             decide(c, c.approver, %{
               kind: :go_excluding,
               excluded: ["sc-2"],
               note: "sc-2 in safe mode"
             })

    by_target = Enum.group_by(members(c), & &1.metadata["group"]["target_index"])
    assert [%{lifecycle_state: :rejected}] = by_target[1]
    assert [%{lifecycle_state: :queued}] = by_target[0]
    assert queue_count(c) == 2
  end

  test "send back and NO-GO reject every member and need a note", c do
    assert {:error, :note_required} = decide(c, c.approver, %{kind: :no_go})

    assert {:ok, %{state: :sent_back}} =
             decide(c, c.approver, %{kind: :send_back, note: "Wrong amount"})

    assert Enum.all?(members(c), &(&1.lifecycle_state == :rejected))
    assert queue_count(c) == 0
    assert {:error, :command_group_not_pending} = decide(c, c.approver, %{kind: :go})
  end

  test "the requester can't approve, and a named approver is enforced", c do
    assert {:error, :command_group_self_approval_not_allowed} = decide(c, c.scope, %{kind: :go})

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 3})], %{
        log_entry: "x",
        requested_approver_user_id: "someone"
      })

    {:ok, named} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    assert {:error, :not_the_requested_approver} =
             GroupDecision.decide(c.approver, c.mission, named.command_group_id, %{kind: :go})
  end

  test "a stale review token is refused", c do
    assert {:error, :command_group_review_stale} =
             decide(c, c.approver, %{kind: :go, expected_review: "old"})
  end
end
