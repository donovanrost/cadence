defmodule Cadence.Reads.CommandGroups.GoUnreleasedTest do
  @moduledoc """
  E2 (#546): the groups a withdrawn model approval touches after their GO, and the Commands list
  filtered by the revision (`withdrawn_revision`).
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures
  import Ecto.Query

  alias Cadence.Commanding.CommandQueueEntryRow
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandGroups

  @craft 4

  setup do
    c = setup!(@craft)
    pin_fleet!(c)
    c
  end

  defp submit!(c, craft, counter \\ 1, acks \\ []) do
    draft = draft(craft, [command(c, "SET_SIGNED", %{"counter" => counter})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft,
        preflight_digest: digest(c, draft),
        hold_acks: acks
      )

    group
  end

  # A group armed after the withdrawal has to carry its acknowledgement; these are armed first.
  defp withdraw!(c), do: withdraw_approval!(c)

  defp read(c, opts \\ []), do: CommandGroups.go_unreleased(c.org, c.mission, c.revision_id, opts)

  test "nothing is affected until an approval is withdrawn", c do
    submit!(c, c.spacecraft)
    assert read(c) == %{groups: [], total: 0}
  end

  test "an unknown revision, or another mission's, is empty", c do
    submit!(c, c.spacecraft)
    withdraw!(c)

    assert CommandGroups.go_unreleased(c.org, c.mission, "no-such-revision") ==
             %{groups: [], total: 0}

    other = setup!(1, "other")
    pin_fleet!(other)
    submit!(other, other.spacecraft)
    withdraw!(other)

    assert CommandGroups.go_unreleased(c.org, c.mission, other.revision_id) ==
             %{groups: [], total: 0}

    # And the other mission's group is not in this mission's answer.
    assert %{total: 1, groups: [%{group_id: id}]} = read(c)
    assert {:ok, _group} = GroupStore.fetch(c.org, c.mission, id)
  end

  test "an armed group with members waiting for their contact is listed, with its craft", c do
    group = submit!(c, c.spacecraft)
    withdraw!(c)

    assert %{total: 1, groups: [listed]} = read(c)
    assert listed.group_id == group.command_group_id
    assert listed.name == group.title
    assert listed.spacecraft_ids == c.spacecraft
    assert listed.state == :queued
    assert listed.go_at == group.requested_at
  end

  test "only the craft that run the revision and still wait are listed", c do
    [first, second | _] = c.spacecraft
    group = submit!(c, [first, second])
    withdraw!(c)

    # `first`'s member has been released: it no longer waits for its contact.
    [entry_first | _] = pending_entries(c, group, first)

    Repo.update_all(
      from(q in CommandQueueEntryRow, where: q.command_queue_entry_id == ^entry_first),
      set: [lifecycle_state: "released"]
    )

    assert %{total: 1, groups: [%{spacecraft_ids: [^second]}]} = read(c)

    # With every member released the group is no longer one a withdrawal reaches.
    [entry_second | _] = pending_entries(c, group, second)

    Repo.update_all(
      from(q in CommandQueueEntryRow, where: q.command_queue_entry_id == ^entry_second),
      set: [lifecycle_state: "released"]
    )

    assert read(c) == %{groups: [], total: 0}
  end

  test "newest GO first, limited, with the full total", c do
    for i <- 1..3, do: submit!(c, [Enum.at(c.spacecraft, i - 1)], i)
    withdraw!(c)

    assert %{total: 3, groups: all} = read(c)
    assert length(all) == 3
    assert all == Enum.sort_by(all, & &1.go_at, {:desc, DateTime})

    assert %{total: 3, groups: [newest]} = read(c, limit: 1)
    assert newest == hd(all)
    assert %{total: 3, groups: [_, _, _]} = read(c, limit: 9_999)
  end

  test "the same number of queries for one group and for several", c do
    submit!(c, [hd(c.spacecraft)])
    withdraw!(c)
    {few, _} = count_queries(fn -> read(c) end)

    # Armed after the withdrawal, so each carries its acknowledgement.
    for craft <- tl(c.spacecraft) do
      draft = draft([craft], [command(c, "SET_SIGNED", %{"counter" => 1})])
      submit!(c, [craft], 1, withdrawal_ack(c, draft))
    end

    {many, %{total: 4}} = count_queries(fn -> read(c) end)

    assert many == few
  end

  test "the Commands list filtered by the withdrawn revision", c do
    [first, second | _] = c.spacecraft
    on_first = submit!(c, [first], 1)
    on_second = submit!(c, [second], 2)
    withdraw!(c)

    org = c.org
    page = fn opts -> CommandGroups.page(org, c.mission, nil, opts) end

    assert {:ok, %{groups: groups}} = page.(withdrawn_revision: c.revision_id)

    assert groups |> Enum.map(& &1.id) |> Enum.sort() ==
             Enum.sort([on_first.command_group_id, on_second.command_group_id])

    assert {:ok, %{groups: []}} = page.(withdrawn_revision: "no-such-revision")

    # The filter is the mission's: another mission's group never shows, whatever revision it names.
    other = setup!(1, "other")
    pin_fleet!(other)
    submit!(other, other.spacecraft)
    withdraw!(other)
    assert {:ok, %{groups: []}} = page.(withdrawn_revision: other.revision_id)
  end

  defp pending_entries(c, group, craft) do
    ids =
      c.org
      |> GroupStore.members(c.mission, group.command_group_id)
      |> Enum.filter(
        &(&1.source_endpoint_ref == Cadence.SourceEndpoints.managed_source_endpoint_id(craft))
      )
      |> Enum.map(& &1.command_request_id)

    Repo.all(
      from(q in CommandQueueEntryRow,
        where: q.command_request_id in ^ids,
        select: q.command_queue_entry_id
      )
    )
  end

  defp count_queries(fun) do
    ref = make_ref()
    me = self()
    handler = "go-unreleased-#{inspect(ref)}"

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
