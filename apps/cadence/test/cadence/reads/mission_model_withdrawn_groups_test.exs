defmodule Cadence.Reads.MissionModelWithdrawnGroupsTest do
  @moduledoc """
  E2 (#546; the CTO's addition): the withdrawn revision's read, which is also the withdraw answer,
  lists the GO'd, unreleased command groups the withdrawal reaches (`affected_groups`, at most 50,
  plus `affected_groups_count`). Each names at most 5 of its affected craft by name and counts them
  all. A revision that isn't withdrawn carries null for both.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.MissionModelApprovals

  @craft 7

  setup do
    c = setup!(@craft)
    pin_fleet!(c)
    c
  end

  defp submit!(c, craft) do
    draft = draft(craft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft,
        preflight_digest: digest(c, draft),
        hold_acks: []
      )

    group
  end

  defp read!(c) do
    {:ok, view} = MissionModelApprovals.read(c.scope, c.mission, c.revision_id)
    view
  end

  test "an approved revision carries no affected groups", c do
    submit!(c, c.spacecraft)
    assert %{affected_groups: nil, affected_groups_count: nil} = read!(c)
  end

  test "a withdrawn revision lists the GO'd groups it reaches, naming five craft and counting all",
       c do
    group = submit!(c, c.spacecraft)
    withdraw_approval!(c)

    assert %{affected_groups: [listed], affected_groups_count: 1} = read!(c)
    assert listed.group_id == group.command_group_id
    assert listed.name == group.title
    assert listed.state == "queued"
    assert listed.spacecraft_count == @craft
    assert length(listed.spacecraft) == 5
    assert Enum.all?(listed.spacecraft, &(Map.keys(&1) |> Enum.sort() == [:id, :name, :scid]))

    # The first five of the group's craft, by name.
    names = Enum.map(listed.spacecraft, & &1.name)
    assert names == Enum.sort(names)
  end
end
