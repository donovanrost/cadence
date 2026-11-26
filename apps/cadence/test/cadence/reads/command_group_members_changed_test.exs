defmodule Cadence.Reads.CommandGroupMembersChangedTest do
  @moduledoc """
  #120 (ux U92 "Up front"): the group read says whether its member rows still match what was
  submitted, before anyone gives it GO. `members_changed`, `submitted_member_count` and
  `current_member_count` are always present; while the group awaits a decision they are the GO
  refusal's own test and counts, otherwise all three are nil. The read and the GO never disagree.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.CommandMemberFixtures
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Ids
  alias Cadence.Reads.CommandGroups

  setup do
    c = setup!(2)
    approver = operator!(c)

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{
        log_entry: "Reset counters",
        requested_approver_user_id: approver.user.user_id
      })

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    assert group.state == :approval_pending
    [member | _rest] = GroupStore.members(c.org, c.mission, group.command_group_id)
    Map.merge(c, %{group: group, member: member, approver: approver})
  end

  test "an untouched group awaiting GO: unchanged, with both counts; the GO agrees", c do
    assert %{members_changed: false, submitted_member_count: 2, current_member_count: 2} = read(c)
    assert {:ok, %{state: :queued}} = go(c)
  end

  test "a member row added behind the submission: changed, 2 then 3; the GO agrees", c do
    CommandMemberFixtures.insert!(
      c.org,
      %{
        c.member
        | command_request_id: Ids.new("command_request"),
          requested_by: %{"actor_kind" => "user", "user_id" => c.scope.user.user_id}
      },
      group: c.group.command_group_id,
      target_index: 1,
      position: 1
    )

    assert %{members_changed: true, submitted_member_count: 2, current_member_count: 3} = read(c)
    assert {:error, {:command_group_members_changed, 2, 3}} = go(c)
  end

  test "a decided group: all three nil", c do
    assert {:ok, %{state: :rejected}} =
             GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
               kind: :no_go,
               note: "not today"
             })

    view = read(c)

    assert Map.take(view, [:members_changed, :submitted_member_count, :current_member_count]) ==
             %{members_changed: nil, submitted_member_count: nil, current_member_count: nil}
  end

  defp read(c) do
    {:ok, view} =
      CommandGroups.get(c.org, c.mission, c.group.command_group_id, c.approver.user.user_id)

    view
  end

  defp go(c) do
    GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
      kind: :go,
      expected_review: GroupDecision.review_token(c.group)
    })
  end
end
