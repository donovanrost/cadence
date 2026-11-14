defmodule Cadence.Contacts.ReservationWindowTest do
  @moduledoc """
  L14 re-land (lead, after cfe2e95fa's revert): a provider that moves a pass moves its delivery
  activation window with it. The reservation stays confirmed through the proposal, the approval
  and the next answer, and its window columns follow the pass Cadence accepted.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{
    ProviderChangeApprovals,
    ProviderReservationChanges,
    ProviderReservations
  }

  alias Cadence.ProviderChangeFixtures, as: Fixtures

  test "a +60 s shift past the old activation edge keeps the booking confirmed" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1, 0)})
    reservation_id = c.reservation.provider_reservation_id
    shift = &Fixtures.shift(c.baseline[&1], 60)

    # The provider proposes the pass 60 s later, its delivery moved with it (the old window's LOS
    # edge is 30 s after the old LOS, so the new LOS is past it).
    assert {:ok, proposed} =
             Fixtures.advance(c, 2, %{
               "starts_at" => shift.("starts_at"),
               "ends_at" => shift.("ends_at"),
               "delivery_descriptor" => descriptor(c.reservation, 60)
             })

    assert proposed.lifecycle_state == :confirmed

    assert [%{lifecycle_state: :pending_approval} = change] =
             ProviderReservationChanges.list_for_reservation(c.organization_id, reservation_id)

    assert {:ok, _approved} =
             ProviderChangeApprovals.approve(
               c.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Inside the plan"
             )

    # The next answer for the same revision (a re-poll) passes validation against the moved window.
    assert {:ok, polled} =
             Fixtures.advance(c, 2, %{
               "starts_at" => shift.("starts_at"),
               "ends_at" => shift.("ends_at"),
               "delivery_descriptor" => descriptor(c.reservation, 60)
             })

    assert polled.lifecycle_state == :confirmed

    {:ok, stored} = ProviderReservations.fetch(c.organization_id, c.mission_id, reservation_id)
    assert stored.lifecycle_state == :confirmed
    assert DateTime.compare(stored.starts_at, DateTime.add(c.reservation.starts_at, 60)) == :eq
    assert DateTime.compare(stored.ends_at, DateTime.add(c.reservation.ends_at, 60)) == :eq
  end

  # 008 tonight (director 11-14): the provider proposes a move and keeps its delivery on the window
  # still in force until the change is decided. Coverage holds against the accepted window, so the
  # booking isn't failed while the pass flies on it.
  test "a +60 s proposal not yet accepted, with the delivery on the old window, stays confirmed" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1, 0)})
    shift = &Fixtures.shift(c.baseline[&1], 60)

    assert {:ok, proposed} =
             Fixtures.advance(c, 2, %{
               "starts_at" => shift.("starts_at"),
               "ends_at" => shift.("ends_at"),
               "delivery_descriptor" => descriptor(c.reservation, 0)
             })

    assert proposed.lifecycle_state == :confirmed
    assert proposed.last_error_document == %{}
  end

  test "a delivery that changes anything but its activation window still fails closed" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1, 0)})

    assert {:error, {:provider_configuration_failure, failed, _reason}} =
             Fixtures.advance(c, 2, %{
               "delivery_descriptor" =>
                 Map.put(descriptor(c.reservation, 0), "endpoint_ref", "unapproved-endpoint")
             })

    assert failed.lifecycle_state == :failed
  end

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
        "starts_at" => iso(reservation.starts_at, seconds - 30),
        "ends_at" => iso(reservation.ends_at, seconds + 30)
      }
    }
  end

  defp iso(time, seconds), do: time |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
