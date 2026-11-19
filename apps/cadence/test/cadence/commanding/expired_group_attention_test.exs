defmodule Cadence.Commanding.ExpiredGroupAttentionTest do
  @moduledoc "U75: an expired command group is a Now item until an operator marks it as seen."
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{Cancellation, CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Commanding.Groups.{ExpiredGroupAttention, GroupStore}
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.Attention

  setup do
    c = setup!(3)
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    ids =
      c.org
      |> GroupStore.members(c.mission, group.command_group_id)
      |> Enum.map(& &1.command_request_id)

    past = DateTime.add(DateTime.utc_now(), -60)

    Repo.update_all(from(r in CommandRequestRow, where: r.command_request_id in ^ids),
      set: [expires_at: past]
    )

    Repo.update_all(from(q in CommandQueueEntryRow, where: q.command_request_id in ^ids),
      set: [expires_at: past]
    )

    Map.put(c, :group, group)
  end

  test "an expired group raises one info item (nothing went out); seen clears it", c do
    id = c.group.command_group_id
    assert ExpiredGroupAttention.items(c.org, c.mission) == []

    Cancellation.expire_due()

    assert [item] = ExpiredGroupAttention.items(c.org, c.mission)

    assert %{
             id: ^id,
             source: "expired_group",
             severity: "info",
             group: %{id: ^id},
             spacecraft_id: nil,
             target_count: 3,
             sent: 0,
             total: 3,
             actions: ["acknowledge"]
           } = item

    assert %{open: 1} = ExpiredGroupAttention.counts(c.org, c.mission)
    assert {:ok, %{items: items}} = Attention.load(c.scope, c.mission)
    assert Enum.any?(items, &(&1.source == "expired_group" and &1.id == id))

    assert {:ok, %{state: "resolved", resolution: %{action: "acknowledged"}}} =
             ExpiredGroupAttention.acknowledge(c.scope, c.mission, id)

    assert ExpiredGroupAttention.items(c.org, c.mission) == []
    assert %{open: 0} = ExpiredGroupAttention.counts(c.org, c.mission)

    assert [%{id: ^id, action: "acknowledged"}] =
             ExpiredGroupAttention.resolved_since(
               c.org,
               c.mission,
               DateTime.add(DateTime.utc_now(), -60)
             )

    assert {:error, :attention_item_not_found} =
             ExpiredGroupAttention.acknowledge(c.scope, c.mission, id)

    # Seen is on the expired event's payload: the group's log has still just the one line.
    assert [%{kind: :expired}] =
             c.mission |> GroupStore.events(id) |> Enum.filter(&(&1.kind == :expired))
  end
end
