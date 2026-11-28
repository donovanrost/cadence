defmodule Cadence.Commanding.WithdrawnHeadTest do
  @moduledoc """
  E2 x ADR-020 P3 (#1100): a craft that runs a **head** revision (its composition compiled at the
  mission's authored head) has no withdrawal row of its own; its approval is its base's. So the
  HOLD, the arming record, the unattended release's refusal, the group read and the mission's
  affected list all follow the base's withdrawal, exactly as for a craft on the base itself.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding
  alias Cadence.Commanding.CommandQueueEntryRow
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Control.WithdrawnPins
  alias Cadence.Reads.{CommandGroups, CommandPreflight}

  @key "model_approval_withdrawn"

  setup do
    c = setup!(3)
    [on_base, on_head, other_head] = c.spacecraft
    manifests = head_manifests!(c)

    pin_fleet!(c, %{
      on_base => manifests.base,
      on_head => manifests.head,
      other_head => manifests.head
    })

    Map.merge(c, %{
      on_base: on_base,
      on_head: on_head,
      other_head: other_head,
      base_revision: manifests.base["revision_id"],
      head_revision: manifests.head["revision_id"]
    })
  end

  defp routine(c, craft),
    do: draft([craft], [command(c, "SET_SIGNED", %{"counter" => 1})])

  defp submit(c, draft, acks \\ []) do
    GroupSubmission.submit(c.scope, c.mission, draft,
      preflight_digest: digest(c, draft),
      hold_acks: acks
    )
  end

  defp ack(c, draft) do
    {:ok, preflight} = CommandPreflight.run(c.org, c.mission, actor(c), draft)
    check = Enum.find(preflight.checks, &(&1.key == :model_approval_withdrawn))

    [
      %{
        key: @key,
        hold_basis: check.hold_basis,
        note: "Seen.",
        preflight_digest: preflight.digest
      }
    ]
  end

  test "the head is its own revision, and nothing is withdrawn yet", c do
    refute c.head_revision == c.base_revision
    assert WithdrawnPins.for_spacecraft(c.org, c.mission, c.spacecraft) == %{}
    assert WithdrawnPins.affected(c.org, c.mission) == %{}
  end

  test "a craft on a head is pinned to its base's withdrawal, as the craft on the base is", c do
    withdraw_approval!(c, c.base_revision)

    pins = WithdrawnPins.for_spacecraft(c.org, c.mission, c.spacecraft)
    assert Map.keys(pins) |> Enum.sort() == Enum.sort(c.spacecraft)

    # Every pin names the withdrawn base, and the same decision: one hold_basis for all.
    assert pins |> Map.values() |> Enum.map(& &1.revision_id) |> Enum.uniq() == [c.base_revision]
    assert pins |> Map.values() |> Enum.map(& &1.hold_basis) |> Enum.uniq() |> length() == 1
    assert pins[c.on_head].hold_basis =~ "#{c.base_revision}:withdrawn:"

    # And each says which revision its craft runs.
    assert pins[c.on_base].running_revision_id == c.base_revision
    assert pins[c.on_head].running_revision_id == c.head_revision

    # The mission's affected list is keyed by the withdrawn revision, with every craft on it.
    affected = WithdrawnPins.affected(c.org, c.mission)
    assert Map.keys(affected) == [c.base_revision]
    assert Enum.sort(affected[c.base_revision]) == Enum.sort(c.spacecraft)
  end

  test "the read takes the same queries for a craft on the base as for crafts on heads", c do
    withdraw_approval!(c, c.base_revision)

    {one, _} =
      count_queries(fn -> WithdrawnPins.for_spacecraft(c.org, c.mission, [c.on_base]) end)

    {all, pins} =
      count_queries(fn -> WithdrawnPins.for_spacecraft(c.org, c.mission, c.spacecraft) end)

    assert map_size(pins) == 3
    assert all <= one + 1, "#{one} queries for one craft, #{all} for three on a head"
  end

  test "preflight HOLDs a craft on a head whose base is withdrawn", c do
    withdraw_approval!(c, c.base_revision)

    {:ok, preflight} =
      CommandPreflight.run(c.org, c.mission, actor(c), routine(c, c.on_head))

    assert %{result: :hold, hold_basis: basis} =
             Enum.find(preflight.checks, &(&1.key == :model_approval_withdrawn))

    assert basis ==
             WithdrawnPins.basis(
               Map.take(WithdrawnPins.for_spacecraft(c.org, c.mission, [c.on_head]), [c.on_head])
             )
  end

  test "armed knowing, a head craft passes an unattended release; armed unaware, it is refused",
       c do
    # Armed before the withdrawal (it knew of none), then the base is withdrawn.
    {:ok, unaware} = submit(c, routine(c, c.on_head))
    [member] = GroupStore.members(c.org, c.mission, unaware.command_group_id)
    withdraw_approval!(c, c.base_revision)

    assert {:error, :model_approval_withdrawn_after_go} = release(c, member)

    # Armed with the HOLD acknowledged, it knew: the release isn't refused for the withdrawal.
    draft = routine(c, c.other_head)
    {:ok, aware} = submit(c, draft, ack(c, draft))
    [known] = GroupStore.members(c.org, c.mission, aware.command_group_id)
    refute {:error, :model_approval_withdrawn_after_go} == release(c, known)
  end

  test "the group read flags a head craft's target, naming the base", c do
    {:ok, group} = submit(c, routine(c, c.on_head))
    withdraw_approval!(c, c.base_revision)

    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)

    assert %{count: 1} = view.withdrawn_after_go
    assert [%{withdrawn_after_go: %{revision_id: revision}}] = view.targets
    assert revision == c.base_revision
  end

  defp release(c, member) do
    entry =
      Repo.get_by!(CommandQueueEntryRow, command_request_id: member.command_request_id)

    Commanding.release_command_queue_entry(
      c.org,
      c.mission,
      entry.command_queue_entry_id,
      "no-such-contact",
      %{},
      unattended: true
    )
  end

  defp count_queries(fun) do
    ref = make_ref()
    me = self()
    handler = "withdrawn-head-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _cfg -> if self() == me, do: send(me, {:query, ref}) end,
      nil
    )

    try do
      result = fun.()
      {drain(ref, 0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, n) do
    receive do
      {:query, ^ref} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end
end
