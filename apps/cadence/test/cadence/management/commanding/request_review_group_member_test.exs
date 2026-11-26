defmodule Cadence.Management.Commanding.RequestReviewGroupMemberTest do
  @moduledoc """
  The ops review page's decision on a command-group member is refused in the words for the
  decision tried (ux U87, amended, #121): approve points to the group's GO/NO-GO, reject to its
  NO-GO. Nothing is recorded either way (the domain refusal is covered by
  `Cadence.Control.Commanding.GroupMemberStandaloneApprovalTest`).
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Management.Commanding.RequestReview

  setup do
    c = setup!(2)

    draft =
      draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "Reset"})

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    [member | _rest] = GroupStore.members(c.org, c.mission, group.command_group_id)
    Map.merge(c, %{group: group, member: member, other: operator!(c, "Third Operator")})
  end

  test "approve is refused in the approve words", c do
    assert {:rejected,
            "This command is part of a command group. Approve it with the group's GO/NO-GO."} =
             decide(c, "approved")

    assert_member_pending(c)
  end

  test "reject is refused in the reject words", c do
    assert {:rejected,
            "This command is part of a command group. Reject it with the group's NO-GO."} =
             decide(c, "rejected")

    assert_member_pending(c)
  end

  defp decide(c, decision) do
    {:ok, request} =
      Commanding.fetch_command_request(c.org, c.mission, c.member.command_request_id)

    RequestReview.decide(c.other, c.mission, c.member.command_request_id, %{
      "decision" => decision,
      "reason" => "deciding one member alone",
      "expected_review" => RequestReview.review_token(request)
    })
  end

  defp assert_member_pending(c) do
    [member] =
      c.org
      |> GroupStore.members(c.mission, c.group.command_group_id)
      |> Enum.filter(&(&1.command_request_id == c.member.command_request_id))

    assert member.lifecycle_state == :approval_pending
  end
end
