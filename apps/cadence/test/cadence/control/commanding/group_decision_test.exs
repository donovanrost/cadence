defmodule Cadence.Control.Commanding.GroupDecisionTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
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
               note: "sc-2 in safe mode",
               expected_review: GroupDecision.review_token(c.group)
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

  test "a stale review token is refused", c do
    assert {:error, :command_group_review_stale} =
             decide(c, c.approver, %{kind: :go, expected_review: "old"})
  end
end
