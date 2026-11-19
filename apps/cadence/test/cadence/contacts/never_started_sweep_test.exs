defmodule Cadence.Contacts.NeverStartedSweepTest do
  @moduledoc """
  The orphan sweep (director, lead 11-14): a realized contact that never started is closed once
  its window has ended (plus a grace), or an hour after a hand start, and is never picked for
  replay.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Contacts

  alias Cadence.Contacts.{
    ContactSettlement,
    ContactStore,
    Path,
    RealizedContact,
    ScheduledContact
  }

  @org "org-never-started"
  @mission "mission-never-started"

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "a past-window contact and an hour-old hand start close; recent ones are left alone" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ended = scheduled_contact!("ended", DateTime.add(now, -1_800), DateTime.add(now, -600))
    graced = scheduled_contact!("graced", DateTime.add(now, -900), DateTime.add(now, -120))
    old_hand = hand_start!("old-hand", DateTime.add(now, -7_200))
    new_hand = hand_start!("new-hand", DateTime.add(now, -1_800))

    assert {:ok, _} = Contacts.reconcile(@mission, now)

    assert %{
             lifecycle_state: :stopped,
             metadata: %{"not_started" => %{"reason" => "window_ended"}}
           } =
             fetch(ended)

    assert %{
             lifecycle_state: :stopped,
             metadata: %{"not_started" => %{"reason" => "never_started"}}
           } =
             fetch(old_hand)

    assert %{lifecycle_state: :defined} = fetch(graced)
    assert %{lifecycle_state: :defined} = fetch(new_hand)

    for id <- [ended, old_hand] do
      assert %{"state" => "settled", "runtime" => "absent", "inspected_at" => at} =
               fetch(id).metadata["settlement"]

      assert is_binary(at)
    end

    # Never replay-selected, even if a journal for them were on disk (39LEY's path).
    journaled = MapSet.new([ended, old_hand])
    assert ContactSettlement.next_replay(@mission, journaled, [], DateTime.add(now, 60)) == nil
  end

  defp fetch(id) do
    {:ok, contact} = ContactStore.fetch_realized(@mission, id)
    contact
  end

  defp scheduled_contact!(name, starts_at, ends_at) do
    scheduled_id = "scheduled-never-started-" <> name

    {:ok, _} =
      Contacts.persist_scheduled_contact(
        @org,
        ScheduledContact.new(%{
          scheduled_contact_id: scheduled_id,
          mission_id: @mission,
          source_endpoint_refs: [],
          starts_at: starts_at,
          ends_at: ends_at,
          paths: [
            Path.new(%{path_id: "downlink", direction: :downlink, selection_role: :selected})
          ]
        })
      )

    realized!(scheduled_id <> "_run", scheduled_id, starts_at)
  end

  defp hand_start!(name, realized_at),
    do: realized!("hand-never-started-" <> name, nil, realized_at)

  defp realized!(id, scheduled_id, realized_at) do
    {:ok, _} =
      Contacts.persist_realized_contact(
        @org,
        RealizedContact.new(%{
          realized_contact_id: id,
          organization_id: @org,
          mission_id: @mission,
          scheduled_contact_id: scheduled_id,
          source_endpoint_refs: [],
          paths: [],
          realized_at: realized_at
        })
      )

    id
  end
end
