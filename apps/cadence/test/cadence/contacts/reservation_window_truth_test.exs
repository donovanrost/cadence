defmodule Cadence.Contacts.ReservationWindowTruthTest do
  @moduledoc """
  Window truth (director 11-14): the window that drives a pass's runtime and its release gate is
  the provider's accepted one. An observed change, or one the provider already made effective,
  moves the reservation's accepted window and the pass's scheduled contact in the same
  transaction (003's 12:10:57Z pass ran on the pre-shift window). A proposal moves nothing until
  it's decided.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.CommandWindow
  alias Cadence.Contacts
  alias Cadence.Contacts.{ContactStore, ProviderReservations, ScheduledContactRevisions}
  alias Cadence.ProviderChangeFixtures, as: Fixtures

  describe "an effective provider shift" do
    test "30 s later moves the scheduled contact, with its before and after recorded" do
      c = setup!()
      shift_effective!(c, 30)

      contact = scheduled(c)
      assert_moved(contact, c.reservation, 30)
      assert contact.current_revision == 2

      assert [_, %{reason_document: reason}] = revisions(c)
      assert reason["kind"] == "provider_change"
      assert reason["before"]["starts_at"] == DateTime.to_iso8601(c.reservation.starts_at)

      assert reason["after"]["starts_at"] ==
               c.reservation.starts_at |> DateTime.add(30) |> DateTime.to_iso8601()

      # Its timeline event (api, ux U56): one, subject the scheduled contact, with the deltas.
      assert [event] =
               c.organization_id
               |> Contacts.list_contact_actions(c.mission_id, [])
               |> Enum.filter(&(&1.action_kind == :contact_window_moved))

      assert event.scheduled_contact_id == c.reservation.scheduled_contact_id
      assert event.realized_contact_id == nil

      assert %{
               "provider_reservation_id" => reservation_id,
               "provider_name" => provider_name,
               "start_delta_s" => 30,
               "end_delta_s" => 30,
               "classification" => "acknowledgment_required",
               "before" => %{"starts_at" => _},
               "after" => %{"ends_at" => _}
             } = event.metadata

      assert reservation_id == c.reservation.provider_reservation_id
      assert provider_name == c.provider.display_name
    end

    test "60 s earlier moves it earlier" do
      c = setup!()
      shift_effective!(c, -60)
      assert_moved(scheduled(c), c.reservation, -60)
    end
  end

  describe "a live pass" do
    test "keeps running and its end follows a later shift" do
      c = setup!()
      realized = realized_active!(c)
      shift_effective!(c, 60)

      contact = scheduled(c)
      assert contact.lifecycle_state == :realized
      assert_moved(contact, c.reservation, 60)
      assert {:ok, %{lifecycle_state: :active}} = fetch_realized(c, realized)
    end

    test "has its end pulled in by an earlier shift" do
      c = setup!()
      _realized = realized_active!(c)
      shift_effective!(c, -60)

      contact = scheduled(c)
      assert DateTime.compare(contact.ends_at, DateTime.add(c.reservation.ends_at, -60)) == :eq
    end
  end

  test "a proposal moves neither the reservation nor the contact until it's decided" do
    c = setup!()

    assert {:ok, _proposed} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 30),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 30),
               "delivery_descriptor" => descriptor(c.reservation, 30)
             })

    assert_moved(scheduled(c), c.reservation, 0)

    {:ok, reservation} =
      ProviderReservations.fetch(
        c.organization_id,
        c.mission_id,
        c.reservation.provider_reservation_id
      )

    assert DateTime.compare(reservation.starts_at, c.reservation.starts_at) == :eq
  end

  test "an aligned contact's release gate opens at the shifted AOS, not the old one" do
    c = setup!()
    realized = realized_active!(c)
    shift_effective!(c, 30)

    {:ok, realized} = fetch_realized(c, realized)
    new_aos = DateTime.add(c.reservation.starts_at, 30)

    assert {:error, {:command_window_closed, _, :outside_pass}} =
             CommandWindow.check(
               c.organization_id,
               c.mission_id,
               realized,
               DateTime.add(new_aos, -1)
             )

    assert :ok = CommandWindow.check(c.organization_id, c.mission_id, realized, new_aos)

    # And it stays open past the old LOS, until the new one.
    old_los = c.reservation.ends_at

    assert :ok =
             CommandWindow.check(
               c.organization_id,
               c.mission_id,
               realized,
               DateTime.add(old_los, 10)
             )
  end

  defp setup!,
    do: Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1, 0)})

  # The provider moves the pass by `seconds` and says it already took effect.
  defp shift_effective!(c, seconds) do
    assert {:ok, _reservation} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], seconds),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], seconds),
               "delivery_descriptor" => descriptor(c.reservation, seconds),
               "extensions" => %{
                 "provider_change" => %{"effective" => true, "rejectable" => false}
               }
             })
  end

  defp assert_moved(contact, reservation, seconds) do
    assert DateTime.compare(contact.starts_at, DateTime.add(reservation.starts_at, seconds)) ==
             :eq

    assert DateTime.compare(contact.ends_at, DateTime.add(reservation.ends_at, seconds)) == :eq
  end

  # The pass realized and running (lifecycle :active), with its runtime stopped at once so the
  # fixture's listener port is free.
  defp realized_active!(c) do
    {:ok, realized} =
      Contacts.realize_scheduled_contact(
        c.organization_id,
        c.mission_id,
        c.reservation.scheduled_contact_id,
        []
      )

    _ = Cadence.Runtime.terminate_realized_contact(c.mission_id, realized.realized_contact_id)
    {:ok, realized} = ContactStore.update_realized_lifecycle(realized, :active, %{})
    realized
  end

  defp fetch_realized(c, realized),
    do: ContactStore.fetch_realized(c.organization_id, c.mission_id, realized.realized_contact_id)

  defp scheduled(c) do
    {:ok, contact} =
      Contacts.fetch_scheduled_contact(
        c.organization_id,
        c.mission_id,
        c.reservation.scheduled_contact_id
      )

    contact
  end

  defp revisions(c),
    do: ScheduledContactRevisions.list(c.organization_id, c.reservation.scheduled_contact_id)

  # The fixture transport's delivery, active 30 s either side of the pass shifted by `seconds`.
  defp descriptor(reservation, seconds) do
    %{
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "protocol" => "tcp",
      "endpoint_ref" => reservation.delivery_profile_ref["id"],
      "framing" => %{"family" => "ccsds_tm", "frame_bytes" => 1115},
      "allowed_source_refs" => [reservation.provider_spacecraft_ref],
      "credential_ref" => nil,
      "activation_window" => %{
        "starts_at" =>
          reservation.starts_at |> DateTime.add(seconds - 30) |> DateTime.to_iso8601(),
        "ends_at" => reservation.ends_at |> DateTime.add(seconds + 30) |> DateTime.to_iso8601()
      }
    }
  end
end
