defmodule Cadence.Reads.PassReservationTest do
  @moduledoc "L14 / A11: a pass's reservation links, provider values and audit."
  use Cadence.DataCase, async: false

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias Cadence.Reads.PassReservation

  setup do
    c = Fixtures.setup_contact()

    # The provider moves the window by a minute: requested and confirmed now differ.
    assert {:ok, _} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 60),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 60)
             })

    c
  end

  defp load(c, cursor \\ nil),
    do:
      PassReservation.load(
        c.organization_id,
        c.mission_id,
        c.reservation.provider_reservation_id,
        cursor
      )

  test "names the reservation's links and every provider field's three values", c do
    assert {:ok, %{reservation: reservation, values: values, audit: audit}} = load(c)

    assert %{
             id: id,
             provider: %{id: provider_id},
             lifecycle_state: state,
             provider_revision: revision
           } = reservation

    assert id == c.reservation.provider_reservation_id
    assert provider_id == c.provider.provider_id
    assert is_binary(state) and is_integer(revision)

    assert Enum.map(values, & &1.field) ==
             ~w(provider_contact_ref opportunity_ref spacecraft_ref ground_station_ref antenna_or_service_pool_ref service_profile_ref delivery_profile_ref starts_at ends_at status pass_phase delivery_state status_reason)

    starts = Enum.find(values, &(&1.field == "starts_at"))
    assert starts.differs
    assert is_binary(starts.confirmed_json)
    assert starts.restricted == false

    assert %{entries: entries, next_cursor: nil} = audit
    assert is_list(entries)
  end

  test "a structured or oversized provider value is withheld, never shown", c do
    row = Repo.get!(ProviderReservationRow, c.reservation.provider_reservation_id)
    requested = JsonDocument.unwrap_value(row.requested_snapshot_document)

    requested =
      Map.merge(requested, %{
        "status_reason" => %{"provider" => %{"internal" => "detail"}},
        "pass_phase" => String.duplicate("x", 600)
      })

    row
    |> Ecto.Changeset.change(requested_snapshot_document: JsonDocument.wrap_value(requested))
    |> Repo.update!()

    assert {:ok, %{values: values}} = load(c)

    for field <- ~w(status_reason pass_phase) do
      row = Enum.find(values, &(&1.field == field))
      assert row.restricted and row.requested_json == nil, field
    end
  end

  test "an unknown pass or a stale audit cursor is refused", c do
    assert {:error, :pass_not_found} =
             PassReservation.load(c.organization_id, c.mission_id, "nope", nil)

    assert {:error, :invalid_cursor} = load(c, "nope")
  end
end
