defmodule Cadence.Contacts.ProviderReservationChangesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{ProviderReservationChanges, ProviderReservations}
  alias Cadence.ProviderChangeFixtures

  test "revision one establishes requested, confirmed, and accepted truth" do
    context = ProviderChangeFixtures.setup_contact()
    reservation = context.reservation

    assert reservation.provider_revision == 1
    assert reservation.requested_snapshot_document != %{}

    assert reservation.provider_confirmed_snapshot_document["ground_station_ref"] ==
             "station-alpha"

    assert reservation.cadence_accepted_snapshot_document ==
             reservation.provider_confirmed_snapshot_document

    assert [] ==
             ProviderReservationChanges.list_for_reservation(
               context.organization_id,
               reservation.provider_reservation_id
             )
  end

  test "material schedule proposal waits for approval without rewriting execution" do
    context = ProviderChangeFixtures.setup_contact()
    shifted_start = ProviderChangeFixtures.shift(context.baseline["starts_at"], 90)
    shifted_end = ProviderChangeFixtures.shift(context.baseline["ends_at"], 90)

    assert {:ok, reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => shifted_start,
               "ends_at" => shifted_end
             })

    assert [change] = changes(context)
    assert change.classification == :approval_required
    assert change.lifecycle_state == :pending_approval
    assert change.actionable
    assert reservation.provider_revision == 2
    assert reservation.provider_confirmed_snapshot_document["starts_at"] == shifted_start
    refute reservation.cadence_accepted_snapshot_document["starts_at"] == shifted_start

    assert {:ok, scheduled} =
             Cadence.Contacts.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.scheduled_contact_id
             )

    assert DateTime.to_iso8601(scheduled.starts_at) == context.baseline["starts_at"]
    assert scheduled.current_revision == 1
  end

  test "a later provider revision supersedes the pending proposal" do
    context = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 60)
             })

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 3, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 120),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 120)
             })

    assert [first, second] = changes(context)
    assert first.lifecycle_state == :superseded
    assert second.lifecycle_state == :pending_approval
    assert second.from_provider_revision == 2
  end

  test "Contact configuration changes fail closed before schedule policy" do
    context = ProviderChangeFixtures.setup_contact(%{"mode" => "bounded_automatic"})

    assert {:error, {:provider_configuration_failure, _reservation, _reason}} =
             ProviderChangeFixtures.advance(context, 2, %{
               "spacecraft_ref" => "different-spacecraft"
             })

    assert [change] = changes(context)
    assert change.classification == :configuration_failure
    assert change.lifecycle_state == :configuration_failure

    assert {:ok, scheduled} =
             Cadence.Contacts.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               context.reservation.scheduled_contact_id
             )

    assert scheduled.current_revision == 1
  end

  test "already-effective cancellation becomes acknowledgment work and reconciles provider truth" do
    context = ProviderChangeFixtures.setup_contact()

    assert {:ok, reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "status" => "canceled",
               "extensions" => %{
                 "provider_change" => %{"effective" => true, "rejectable" => false}
               }
             })

    assert reservation.lifecycle_state == :canceled
    assert [change] = changes(context)
    assert change.lifecycle_state == :acknowledgment_required
    assert change.already_effective
    refute change.actionable

    assert {:ok, scheduled} =
             Cadence.Contacts.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.scheduled_contact_id
             )

    assert scheduled.lifecycle_state == :canceled
    assert scheduled.current_revision == 1
  end

  test "bounded policy acceptance applies the exact provider revision once" do
    context =
      ProviderChangeFixtures.setup_contact(%{
        "mode" => "bounded_automatic",
        "maximum_later_start_shift_seconds" => 30,
        "maximum_later_end_shift_seconds" => 30
      })

    shifted_start = ProviderChangeFixtures.shift(context.baseline["starts_at"], 30)
    shifted_end = ProviderChangeFixtures.shift(context.baseline["ends_at"], 30)

    assert {:ok, reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => shifted_start,
               "ends_at" => shifted_end
             })

    assert [change] = changes(context)
    assert change.classification == :policy_accept
    assert change.lifecycle_state == :policy_accepted
    assert reservation.cadence_accepted_snapshot_document["provider_revision"] == 2

    assert {:ok, scheduled} =
             Cadence.Contacts.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.scheduled_contact_id
             )

    assert DateTime.to_iso8601(scheduled.starts_at) == shifted_start
    assert scheduled.current_revision == 2

    assert {:ok, replayed} =
             ProviderReservations.apply_provider_status(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               Map.merge(context.baseline, %{
                 "provider_revision" => 2,
                 "starts_at" => shifted_start,
                 "ends_at" => shifted_end
               })
             )

    assert replayed.provider_revision == 2

    assert {:ok, same_schedule} =
             Cadence.Contacts.fetch_scheduled_contact(
               context.organization_id,
               context.mission_id,
               reservation.scheduled_contact_id
             )

    assert same_schedule.current_revision == 2
  end

  defp changes(context) do
    ProviderReservationChanges.list_for_reservation(
      context.organization_id,
      context.reservation.provider_reservation_id
    )
  end
end
