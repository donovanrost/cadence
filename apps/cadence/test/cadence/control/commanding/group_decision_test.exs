defmodule Cadence.Control.Commanding.GroupDecisionTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Commanding.{CommandApprovalRow, CommandQueueEntryRow}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Commanding.RequestDigest
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Management.Commanding.ApprovedCommand

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

  defp excluded_endpoints(_c),
    do:
      Enum.sort(
        for i <- [1, 3], do: Cadence.SourceEndpoints.managed_source_endpoint_id("sc-#{i}")
      )

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
               note: "sc-2 in safe mode",
               expected_review: GroupDecision.review_token(c.group)
             })

    by_target = Enum.group_by(members(c), & &1.group_slot.target_index)
    assert [%{lifecycle_state: :rejected}] = by_target[1]
    assert [%{lifecycle_state: :queued}] = by_target[0]
    assert queue_count(c) == 2
  end

  # #795: the exclusion is bound by the rows it leaves, not by a separate digest. The review token
  # binds the GO to the members it covered; each approved member is queued with its own approved
  # hash and each excluded one is rejected, in the append-only approvals.
  test "GO excluding leaves exactly the excluded targets' members rejected and unqueued, the rest approved with their hash",
       c do
    covered = GroupDecision.members_digest(c.group)

    assert {:ok, group} =
             decide(c, c.approver, %{
               kind: :go_excluding,
               excluded: ["sc-1", "sc-3"],
               note: "in safe mode",
               expected_review: GroupDecision.review_token(c.group)
             })

    {out, kept} = Enum.split_with(members(c), &(&1.group_slot.target_index in [0, 2]))
    assert Enum.map(out, & &1.source_endpoint_ref) |> Enum.sort() == excluded_endpoints(c)
    assert [%{group_slot: %{target_index: 1}}] = kept

    out_ids = Enum.map(out, & &1.command_request_id)
    kept_ids = Enum.map(kept, & &1.command_request_id)

    assert Enum.all?(out, &(&1.lifecycle_state == :rejected))
    assert Enum.all?(kept, &(&1.lifecycle_state == :queued))

    entries = Repo.all(from(q in CommandQueueEntryRow, where: q.mission_id == ^c.mission))
    assert Enum.map(entries, & &1.command_request_id) == kept_ids

    approvals =
      from(a in CommandApprovalRow, where: a.mission_id == ^c.mission)
      |> Repo.all()
      |> Map.new(&{&1.command_request_id, &1})

    assert Map.keys(approvals) |> Enum.sort() == Enum.sort(out_ids ++ kept_ids)
    assert Enum.all?(out_ids, &(approvals[&1].decision == "rejected"))
    assert Enum.all?(out_ids, &(approvals[&1].reason == "Excluded at review: in safe mode"))
    assert Enum.all?(kept_ids, &(approvals[&1].decision == "approved"))

    # Each approval names the member's own review token as the approver saw it, before the GO.
    for member <- kept ++ out do
      assert approvals[member.command_request_id].subject_digest ==
               RequestDigest.digest(%{member | lifecycle_state: :approval_pending})
    end

    [kept_member] = kept
    [entry] = entries

    {:ok, approved} =
      ApprovedCommand.new(
        %{kept_member | lifecycle_state: :approved},
        CommandApprovalRow.to_domain(approvals[kept_member.command_request_id])
      )

    assert CommandQueueEntryRow.to_domain(entry).metadata[
             "approved_content_sha256"
           ] == approved.content_sha256

    assert group.decision["excluded"] == ["sc-1", "sc-3"]
    assert group.decision["excluded_request_ids"] == Enum.sort(out_ids)
    assert group.decision["members_digest"] == covered
  end

  test "an exclusion that repeats a target, or names one the group doesn't have, is refused", c do
    review = GroupDecision.review_token(c.group)

    assert {:error, {:invalid_params, %{"excluded" => _}}} =
             decide(c, c.approver, %{
               kind: :go_excluding,
               excluded: ["sc-2", "sc-2"],
               note: "x",
               expected_review: review
             })

    assert {:error, :unknown_excluded_target} =
             decide(c, c.approver, %{
               kind: :go_excluding,
               excluded: ["sc-2", "nobody"],
               note: "x",
               expected_review: review
             })

    assert Enum.all?(members(c), &(&1.lifecycle_state == :approval_pending))
    assert queue_count(c) == 0
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

  # #622 (#280; ca-security P2): a group's requester counts as people, as a single request's does.
  test "a service-requested group refuses the service's accountable person and accepts another admin",
       c do
    {:ok, %{service_identity: service}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          display_name: "Release bot",
          capabilities: [:mission_admin]
        }),
        c.approver
      )

    service_id = service.service_identity_id
    as_requested_by(c, %{"actor_kind" => "service", "service_identity_id" => service_id})

    assert {:error,
            {:command_group_self_approval_not_allowed,
             %{via_service: %{id: ^service_id, name: "Release bot"}}}} =
             decide(c, c.approver, %{kind: :go, expected_review: review(c)})

    # api-ops on #626: every decision, not only GO.
    assert {:error,
            {:command_group_self_approval_not_allowed, %{via_service: %{id: ^service_id}}}} =
             decide(c, c.approver, %{kind: :no_go, note: "Not today", expected_review: review(c)})

    other = operator!(c, "Third Operator")
    assert {:ok, _} = decide(c, other, %{kind: :go, expected_review: review(c)})
  end

  test "a decider who isn't a person is refused, on its own (ca-security on #626)", c do
    service_scope = %{c.approver | user: nil}

    assert {:error, _refused} =
             decide(c, service_scope, %{kind: :go, expected_review: review(c)})
  end

  test "a service nobody is accountable for refuses everyone (fail closed)", c do
    as_requested_by(c, %{
      "actor_kind" => "service",
      "service_identity_id" => "service_identity:nobody"
    })

    assert {:error, {:command_group_approver_authors_unknown, %{service: _}}} =
             decide(c, c.approver, %{kind: :go, expected_review: review(c)})
  end

  defp as_requested_by(c, document) do
    Repo.update_all(
      from(g in "command_groups", where: g.command_group_id == ^c.group.command_group_id),
      set: [requested_by_document: %{"value" => document}]
    )
  end

  defp review(c) do
    {:ok, group} = GroupStore.fetch(c.org, c.mission, c.group.command_group_id)
    GroupDecision.review_token(group)
  end

  # #117 step 4a (domain, ca-security): GO must carry the token, and the token covers WHICH
  # requests are members, not only how many (the members digest).
  test "a GO without the review token is refused, fail closed", c do
    assert {:error, :command_group_review_stale} = decide(c, c.approver, %{kind: :go})

    assert {:error, :command_group_review_stale} =
             decide(c, c.approver, %{kind: :go_excluding, excluded: ["sc-2"], note: "x"})
  end

  test "swapping one member for another at the same count changes the token, so GO is refused",
       c do
    token = GroupDecision.review_token(c.group)
    digest = GroupDecision.members_digest(c.group)
    [first | _] = members(c)

    # Another request takes the first member's place: same count, different members.
    Repo.update_all(
      from(r in "command_requests", where: r.command_request_id == ^first.command_request_id),
      set: [command_request_id: first.command_request_id <> "-swapped"]
    )

    refute GroupDecision.members_digest(c.group) == digest

    assert {:error, :command_group_review_stale} =
             decide(c, c.approver, %{kind: :go, expected_review: token})
  end

  # #117 step 4b: each member approval is a complete record, and the group's decision names which
  # members were decided and which a GO excluded.
  test "a GO's records: each member's token, separated_from, admin_mode; the members digest and excluded ids",
       c do
    before = members(c)
    tokens = Map.new(before, &{&1.command_request_id, RequestDigest.digest(&1)})
    digest = GroupDecision.members_digest(c.group)

    assert {:ok, decided} =
             decide(c, c.approver, %{
               kind: :go_excluding,
               excluded: ["sc-2"],
               note: "sc-2 in safe mode",
               expected_review: GroupDecision.review_token(c.group)
             })

    rows =
      Repo.all(from(a in CommandApprovalRow, where: a.command_request_id in ^Map.keys(tokens)))

    assert length(rows) == length(before)

    for row <- rows do
      assert row.subject_digest == Map.fetch!(tokens, row.command_request_id)
      assert row.separated_from == [c.scope.user.user_id]
      assert row.admin_mode == (c.approver.admin_mode? == true)
    end

    excluded =
      before
      |> Enum.filter(&(&1.group_slot.target_index == 1))
      |> Enum.map(& &1.command_request_id)
      |> Enum.sort()

    assert decided.decision["members_digest"] == digest
    assert decided.decision["excluded_request_ids"] == excluded
  end

  test "a stale review token is refused", c do
    assert {:error, :command_group_review_stale} =
             decide(c, c.approver, %{kind: :go, expected_review: "old"})
  end
end
