defmodule Cadence.Contacts.ContactSchedulePagesTest do
  use Cadence.DataCase, async: false
  alias Cadence.Contacts.{ContactStore, ProviderReservations, RealizedContact, ScheduledContact}
  alias Cadence.ProviderChangeFixtures

  test "scheduled and realized ledgers page separately in stable order and enforce both scopes" do
    c = ProviderChangeFixtures.setup_contact()

    for n <- 1..27 do
      id = "ledger-#{String.pad_leading(to_string(n), 2, "0")}"

      {:ok, _} =
        ContactStore.persist_scheduled(
          ScheduledContact.new(%{
            organization_id: c.organization_id,
            scheduled_contact_id: id,
            mission_id: c.mission_id,
            starts_at: ~U[2026-09-09 12:00:00Z],
            ends_at: ~U[2026-09-09 13:00:00Z]
          })
        )

      {:ok, _} =
        ContactStore.persist_realized(
          RealizedContact.new(%{
            organization_id: c.organization_id,
            realized_contact_id: id,
            mission_id: c.mission_id,
            clock_mode: :replay
          })
        )
    end

    for kind <- [:scheduled, :realized] do
      assert {:ok, %{entries: first, more: true}} =
               ContactStore.list_record_page(c.organization_id, c.mission_id, kind, 1)

      assert length(first) == 25

      assert {:ok, %{entries: last, more: false}} =
               ContactStore.list_record_page(c.organization_id, c.mission_id, kind, 2)

      assert length(last) in [2, 3]
      key = if kind == :scheduled, do: :scheduled_contact_id, else: :realized_contact_id

      assert MapSet.disjoint?(
               MapSet.new(first, &Map.fetch!(&1, key)),
               MapSet.new(last, &Map.fetch!(&1, key))
             )

      assert {:ok, %{entries: []}} =
               ContactStore.list_record_page("foreign", c.mission_id, kind, 1)

      assert {:ok, %{entries: []}} =
               ContactStore.list_record_page(c.organization_id, "foreign", kind, 1)
    end
  end

  test "provider reservation pages cap their rows and preserve ordered nonoverlapping identities" do
    c = ProviderChangeFixtures.setup_contact()

    for n <- 1..27 do
      attrs =
        c.reservation
        |> Map.from_struct()
        |> Map.merge(%{
          provider_reservation_id: "reservation-page-#{n}",
          provider_contact_ref: nil,
          idempotency_key: "page-key-#{n}",
          scheduled_contact_id: "schedule-page-#{n}"
        })

      assert {:ok, _} = ProviderReservations.create_attempt(c.organization_id, attrs)
    end

    assert {:ok, %{entries: first, more: true}} =
             ProviderReservations.list_mission_page(c.organization_id, c.mission_id, 1)

    assert {:ok, %{entries: last, more: false}} =
             ProviderReservations.list_mission_page(c.organization_id, c.mission_id, 2)

    assert length(first) == 25
    assert length(last) == 3

    assert MapSet.disjoint?(
             MapSet.new(first, & &1.provider_reservation_id),
             MapSet.new(last, & &1.provider_reservation_id)
           )

    assert {:ok, %{entries: ^first}} =
             ProviderReservations.list_mission_page(c.organization_id, c.mission_id, 1)
  end

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

    assert {:ok, %{entries: [row]}} =
             ProviderReservations.list_mission_page(c.organization_id, c.mission_id, 1)

    assert row.lifecycle_state == :canceling

    assert {:ok, %{entries: []}} =
             ProviderReservations.list_mission_page(c.organization_id, "foreign", 1)
  end
end
