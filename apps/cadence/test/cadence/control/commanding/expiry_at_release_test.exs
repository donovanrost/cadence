defmodule Cadence.Control.Commanding.ExpiryAtReleaseTest do
  @moduledoc """
  A member past its `expires_at` is never released, and ends `expired` when release reaches it,
  not on the dispatcher's next sweep (the sweep is only cleanup). Covers the lane dispatch, the
  claim itself (the race where nothing closed it first) and a named-contact release (U46).
  """
  use Cadence.ConfigCase, async: false

  import Cadence.GroupReleaseFixtures

  alias Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow
  }

  alias Cadence.Control.Commanding
  alias Cadence.Persistence.JsonDocument

  @org "org-group-release"
  @mission "mission-group-release"
  @at ~U[2026-11-14 07:20:00Z]

  setup do
    persist_mission_scope(@org, @mission)
    alpha = persist_target!("alpha", 0)
    model = import_noop_model!()
    scope = CommandGroupFixtures.operator!(%{org: @org}, "Release Operator")

    %{alpha: alpha, model: model, scope: scope}
  end

  test "lane dispatch ends an expired head as expired, never releases it, and releases the next",
       c do
    %{entries: [expired, fresh]} = armed_group!(c, [c.alpha, c.alpha])
    # A booked pass open at @at: an armed group releases by itself only into a scheduled pass.
    uplink_contact!(c.alpha, {DateTime.add(@at, -600), DateTime.add(@at, 600)})
    expire!(expired)

    assert {:ok, _released} =
             Cadence.Commanding.dispatch_queue_lane(
               @org,
               @mission,
               lane(expired),
               %{"actor_kind" => "system"},
               attempted_at: @at
             )

    assert ended_expired?(expired)
    assert attempts(expired) == 0
    assert attempts(fresh) == 1
    assert entry_state(fresh) != "pending"
  end

  test "the claim refuses an expired entry that nothing has closed yet", c do
    %{entries: [expired]} = armed_group!(c, [c.alpha])
    contact = uplink_contact!(c.alpha)
    expire!(expired)

    assert {:error, reason} =
             Cadence.Commanding.release_command_queue_entry(
               @org,
               @mission,
               expired,
               contact.realized_contact_id,
               %{"actor_kind" => "system"},
               attempted_at: @at
             )

    assert match?({:command_queue_entry_expired, _}, reason) or
             match?({:command_request_expired, _}, reason)

    assert attempts(expired) == 0
    assert entry_state(expired) == "pending"
  end

  test "a named-contact release ends an expired member as expired and releases the rest", c do
    group = armed_group!(c, [c.alpha, c.alpha])
    [expired, fresh] = group.entries
    contact = uplink_contact!(c.alpha)
    expire!(expired)

    assert {:ok, %{released_entry_ids: [^fresh], stopped: nil}} =
             Commanding.release_group_to_contact(
               c.scope,
               @mission,
               group.id,
               contact.realized_contact_id,
               confirm_unbooked: true,
               attempted_at: @at
             )

    assert ended_expired?(expired)
    assert attempts(expired) == 0
  end

  test "a named-contact release with only expired members releases nothing", c do
    group = armed_group!(c, [c.alpha])
    [expired] = group.entries
    contact = uplink_contact!(c.alpha)
    expire!(expired)

    assert {:error, {:command_group_nothing_to_release, _contact}} =
             Commanding.release_group_to_contact(
               c.scope,
               @mission,
               group.id,
               contact.realized_contact_id,
               confirm_unbooked: true,
               attempted_at: @at
             )

    assert ended_expired?(expired)
    assert attempts(expired) == 0
  end

  # Expired before the release time and before now: the sweep hasn't run, so it's still pending.
  defp expire!(entry_id) do
    past = DateTime.add(@at, -60)
    entry = Repo.get!(CommandQueueEntryRow, entry_id)

    {1, _} =
      from(q in CommandQueueEntryRow, where: q.command_queue_entry_id == ^entry_id)
      |> Repo.update_all(set: [expires_at: past])

    {1, _} =
      from(r in CommandRequestRow, where: r.command_request_id == ^entry.command_request_id)
      |> Repo.update_all(set: [expires_at: past])
  end

  defp lane(entry_id), do: Repo.get!(CommandQueueEntryRow, entry_id).queue_lane_key

  defp entry_state(entry_id), do: Repo.get!(CommandQueueEntryRow, entry_id).lifecycle_state

  defp request_id(entry_id), do: Repo.get!(CommandQueueEntryRow, entry_id).command_request_id

  defp attempts(entry_id) do
    id = request_id(entry_id)

    Repo.aggregate(
      from(a in CommandReleaseAttemptRow, where: a.command_request_id == ^id),
      :count
    )
  end

  defp ended_expired?(entry_id) do
    request = Repo.get!(CommandRequestRow, request_id(entry_id))
    metadata = JsonDocument.unwrap_value(request.metadata_document)

    entry_state(entry_id) == "canceled" and request.lifecycle_state == "canceled" and
      get_in(metadata, ["cancellation", "reason"]) == "expired"
  end
end
