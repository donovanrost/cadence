defmodule CadenceWeb.Console.CommandGroupMembersChangedJSONTest do
  @moduledoc """
  #120 (ux U92 "Up front"): the group view (show and the channel push both encode it with
  CommandGroupJSON.show/1) always carries `members_changed`, `submitted_member_count` and
  `current_member_count`: the GO refusal's own test while the group awaits a decision, all three
  null otherwise.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Reads.CommandGroups
  alias CadenceWeb.Console.CommandGroupJSON

  @keys ["members_changed", "submitted_member_count", "current_member_count"]

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

    Map.merge(c, %{group: group, approver: approver})
  end

  test "awaiting GO and untouched: false with both counts", c do
    assert Map.take(shown(c), @keys) == %{
             "members_changed" => false,
             "submitted_member_count" => 2,
             "current_member_count" => 2
           }
  end

  test "awaiting GO with a member row taken out: true, 2 then 1", c do
    [member | _] = GroupStore.members(c.org, c.mission, c.group.command_group_id)

    {1, _} =
      Cadence.Repo.update_all(
        from(r in CommandRequestRow, where: r.command_request_id == ^member.command_request_id),
        set: [command_group_id: nil, group_target_index: nil, group_position: nil]
      )

    assert Map.take(shown(c), @keys) == %{
             "members_changed" => true,
             "submitted_member_count" => 2,
             "current_member_count" => 1
           }
  end

  test "decided: the three keys are present and null", c do
    {:ok, _} =
      GroupDecision.decide(c.approver, c.mission, c.group.command_group_id, %{
        kind: :no_go,
        note: "not today"
      })

    shown = shown(c)
    for key <- @keys, do: assert(Map.has_key?(shown, key) and is_nil(shown[key]), key)
  end

  defp shown(c) do
    {:ok, view} =
      CommandGroups.get(c.org, c.mission, c.group.command_group_id, c.approver.user.user_id)

    view |> CommandGroupJSON.show() |> Jason.encode!() |> Jason.decode!()
  end
end
