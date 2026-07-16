defmodule Cadence.Contacts.ScheduledContactRevisionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.ScheduledContactRevisions
  alias Cadence.ProviderChangeFixtures

  test "new Scheduled Contacts receive one immutable initial revision" do
    context = ProviderChangeFixtures.setup_contact()

    assert [revision] =
             ScheduledContactRevisions.list(
               context.organization_id,
               context.reservation.scheduled_contact_id
             )

    assert revision.revision == 1
    assert revision.provider_reservation_change_id == nil
    assert revision.snapshot_document["starts_at"] == context.baseline["starts_at"]

    assert {:ok, fetched} =
             ScheduledContactRevisions.fetch(
               context.organization_id,
               context.reservation.scheduled_contact_id,
               1
             )

    assert fetched == revision
  end

  test "an accepted provider change appends rather than overwrites" do
    context =
      ProviderChangeFixtures.setup_contact(%{
        "mode" => "bounded_automatic",
        "maximum_later_start_shift_seconds" => 10,
        "maximum_later_end_shift_seconds" => 10
      })

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 10),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 10)
             })

    assert [initial, accepted] =
             ScheduledContactRevisions.list(
               context.organization_id,
               context.reservation.scheduled_contact_id
             )

    assert initial.revision == 1
    assert accepted.revision == 2
    assert accepted.provider_reservation_change_id
    refute accepted.snapshot_document == initial.snapshot_document
  end
end
