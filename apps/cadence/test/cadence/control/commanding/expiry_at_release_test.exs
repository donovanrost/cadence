defmodule Cadence.Control.Commanding.ExpiryAtReleaseTest do
  @moduledoc """
  A member past its `expires_at` is never released, and ends `expired` when release reaches it,
  not on the dispatcher's next sweep (the sweep is only cleanup). Covers the lane dispatch, the
  claim itself (the race where nothing closed it first) and a named-contact release (U46).

  DECISIONS #97 (an expired member halts its group) holds because a group's members share ONE
  expires_at (`Groups.Admission.uniform_expiry!/1` is the tripwire): when one expires, every later
  member of its target expires at the same instant and ends `expired` itself, on both paths. The
  tests here expire a group the only way it can: all its unreleased members at once.
  """
  use Cadence.ConfigCase, async: false

  import Cadence.GroupReleaseFixtures

  alias Cadence.CommandGroupFixtures

  alias Cadence.Commanding.{
    Cancellation,
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow
  }

  alias Cadence.Commanding.Groups.{Admission, GroupStore}
  alias Cadence.Control.Commanding
  alias Cadence.Control.Commanding.GroupRelease
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

  test "lane dispatch: when a group expires, every unreleased member ends expired, none goes out",
       c do
    %{entries: entries} = armed_group!(c, [c.alpha, c.alpha, c.alpha])
    # A booked pass open at @at: an armed group releases by itself only into a scheduled pass.
    uplink_contact!(c.alpha, {DateTime.add(@at, -600), DateTime.add(@at, 600)})
    Enum.each(entries, &expire!/1)

    assert {:error, :command_queue_lane_empty} =
             Cadence.Commanding.dispatch_queue_lane(
               @org,
               @mission,
               lane(hd(entries)),
               %{"actor_kind" => "system"},
               attempted_at: @at
             )

    for entry <- entries do
      assert ended_expired?(entry)
      assert attempts(entry) == 0
    end
  end

  test "lane dispatch: members sent before the deadline stay sent; the rest end expired together",
       c do
    %{entries: [first | rest]} = armed_group!(c, [c.alpha, c.alpha, c.alpha])
    uplink_contact!(c.alpha, {DateTime.add(@at, -600), DateTime.add(@at, 600)})

    # The first goes out while the group is live.
    assert {:ok, _} =
             Cadence.Commanding.release_command_queue_entry(
               @org,
               @mission,
               first,
               hd(Cadence.Contacts.list_realized_contacts(@org, @mission)).realized_contact_id,
               %{"actor_kind" => "system"},
               attempted_at: @at
             )

    # Then the group's one deadline passes: the rest expire at the same instant.
    Enum.each(rest, &expire!/1)

    assert {:error, :command_queue_lane_empty} =
             Cadence.Commanding.dispatch_queue_lane(
               @org,
               @mission,
               lane(first),
               %{"actor_kind" => "system"},
               attempted_at: @at
             )

    assert attempts(first) == 1
    assert Enum.all?(rest, &(ended_expired?(&1) and attempts(&1) == 0))

    # U75: the timeline says it once (the read's expiry counts: expiry_sweep_test).
    assert [%{payload: %{"sent" => 1, "not_sent" => 2}, actor: %{"actor_kind" => "system"}}] =
             expired_events(first)

    # A later sweep or path ends nothing new and writes no second event.
    Cancellation.expire_due()
    assert length(expired_events(first)) == 1
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

  test "a named release on an expired group stops at its first member; the rest end expired too",
       c do
    group = armed_group!(c, [c.alpha, c.alpha, c.alpha])
    [first | rest] = group.entries
    contact = uplink_contact!(c.alpha)
    Enum.each(group.entries, &expire!/1)

    assert {:ok,
            %{
              released_entry_ids: [],
              stopped: %{command_queue_entry_id: ^first, reason: reason},
              not_attempted_entry_ids: ^rest
            }} = release(c, group, contact)

    assert reason == {:command_queue_entry_expired, first}
    assert GroupRelease.encode_reason(reason)["code"] == "command_queue_entry_expired"

    # Not left queued to go out at a later contact: each ended expired by its own deadline.
    for entry <- group.entries do
      assert ended_expired?(entry)
      assert attempts(entry) == 0
    end

    assert {:error, {:command_group_nothing_to_release, _}} = release(c, group, contact)
  end

  test "the #97 tripwire: a group whose members don't share one expiry is never admitted" do
    member = fn expires_at -> %{request: %{expires_at: expires_at}} end
    at = DateTime.add(@at, 3_600)

    assert :ok = Admission.uniform_expiry!([member.(at), member.(at)])
    assert :ok = Admission.uniform_expiry!([member.(nil), member.(nil)])

    assert_raise ArgumentError, ~r/DECISIONS #97/, fn ->
      Admission.uniform_expiry!([member.(at), member.(DateTime.add(at, 60))])
    end

    assert_raise ArgumentError, ~r/DECISIONS #97/, fn ->
      Admission.uniform_expiry!([member.(at), member.(nil)])
    end
  end

  defp release(c, group, contact),
    do:
      Commanding.release_group_to_contact(
        c.scope,
        @mission,
        group.id,
        contact.realized_contact_id,
        confirm_unbooked: true,
        attempted_at: @at
      )

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

  defp group_id(entry_id),
    do: Repo.get!(CommandRequestRow, request_id(entry_id)).command_group_id

  defp expired_events(entry_id),
    do: @mission |> GroupStore.events(group_id(entry_id)) |> Enum.filter(&(&1.kind == :expired))

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
