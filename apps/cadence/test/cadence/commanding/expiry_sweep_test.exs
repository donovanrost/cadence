defmodule Cadence.Commanding.ExpirySweepTest do
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{Cancellation, CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandGroups

  setup do
    c = setup!(3)
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    Map.put(c, :group, group)
  end

  defp member_ids(c),
    do:
      c.org
      |> GroupStore.members(c.mission, c.group.command_group_id)
      |> Enum.map(& &1.command_request_id)

  defp set_expired(ids) do
    past = DateTime.add(DateTime.utc_now(), -60)

    Repo.update_all(from(r in CommandRequestRow, where: r.command_request_id in ^ids),
      set: [expires_at: past]
    )

    Repo.update_all(from(q in CommandQueueEntryRow, where: q.command_request_id in ^ids),
      set: [expires_at: past]
    )
  end

  test "expired unstarted members are canceled as expired; others are left alone", c do
    [expired, released, fresh] = member_ids(c)
    set_expired([expired, released])

    Repo.update_all(from(q in CommandQueueEntryRow, where: q.command_request_id == ^released),
      set: [lifecycle_state: "released"]
    )

    assert Cancellation.expire_due() == %{{c.org, c.mission} => 1}

    {:ok, view} = CommandGroups.get(c.org, c.mission, c.group.command_group_id, nil)

    stages =
      view.targets
      |> Enum.flat_map(& &1.members)
      |> Map.new(&{&1.request_id, {&1.stage, &1.end_reason}})

    assert stages[expired] == {:canceled, :expired}
    refute match?({:canceled, _}, stages[fresh])
    refute match?({:canceled, _}, stages[released])

    assert Cancellation.expire_due() == %{}
  end

  test "U75: an expired group's read and timeline say how the expiry went, once", c do
    ids = member_ids(c)
    set_expired(ids)

    assert Cancellation.expire_due() == %{{c.org, c.mission} => 3}

    {:ok, view} = CommandGroups.get(c.org, c.mission, c.group.command_group_id, nil)
    assert %{expired: 3, sent: 0, total: 3} = view.expiry

    [row] =
      c.org
      |> CommandGroups.list(c.mission, nil, states: [:queued])
      |> Enum.filter(&(&1.id == c.group.command_group_id))

    assert row.expiry == view.expiry

    assert [%{kind: :expired, payload: %{"sent" => 0, "not_sent" => 3}}] =
             c.mission
             |> GroupStore.events(c.group.command_group_id)
             |> Enum.filter(&(&1.kind == :expired))
  end

  test "U75: a group none of whose members expired has no expiry", c do
    {:ok, view} = CommandGroups.get(c.org, c.mission, c.group.command_group_id, nil)
    assert view.expiry == nil
  end
end
