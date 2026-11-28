defmodule Cadence.Contacts.ReservationCancellationEvidenceTest do
  use Cadence.DataCase, async: false
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.ProviderChangeFixtures

  test "cancellation claims exactly the reviewed row once and rejects stale or foreign evidence before a provider call" do
    c = ProviderChangeFixtures.setup_contact()
    r = c.reservation

    e = %{
      "provider_revision" => r.provider_revision,
      "lifecycle_state" => to_string(r.lifecycle_state),
      "provider_contact_ref" => r.provider_contact_ref
    }

    assert {:error, :stale_reservation_cancellation_evidence} =
             ProviderReservations.mark_canceling(
               c.organization_id,
               c.mission_id,
               r.provider_reservation_id,
               expected_cancel_evidence: Map.put(e, "provider_revision", r.provider_revision + 1)
             )

    assert {:error, :provider_reservation_not_found} =
             ProviderReservations.mark_canceling(
               "foreign",
               c.mission_id,
               r.provider_reservation_id,
               expected_cancel_evidence: e
             )

    assert {:ok, %{lifecycle_state: :canceling}} =
             ProviderReservations.mark_canceling(
               c.organization_id,
               c.mission_id,
               r.provider_reservation_id,
               expected_cancel_evidence: e
             )

    assert {:error, :stale_reservation_cancellation_evidence} =
             ProviderReservations.mark_canceling(
               c.organization_id,
               c.mission_id,
               r.provider_reservation_id,
               expected_cancel_evidence: e
             )

    assert {:ok, %{lifecycle_state: :canceling}} =
             ProviderReservations.fetch(
               c.organization_id,
               c.mission_id,
               r.provider_reservation_id
             )

    assert {:error, :provider_reservation_not_found} =
             ProviderReservations.fetch(c.organization_id, "foreign", r.provider_reservation_id)
  end
end
