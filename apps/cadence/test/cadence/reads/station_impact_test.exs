defmodule Cadence.Reads.StationImpactTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures, only: [member_scope: 3]

  alias Cadence.Contacts.ProviderReservations
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Reads.StationImpact

  setup do
    c = ProviderChangeFixtures.setup_contact()
    %{c: c, alice: member_scope(c.organization_id, :member, "Alice")}
  end

  # The fixture's pass runs 12:00–12:10 on 2026-07-20 and names no station.
  defp at(minutes), do: DateTime.add(~U[2026-07-20 12:00:00.000000Z], minutes * 60, :second)

  defp reserve!(c, n, station, starts, opts \\ []) do
    snapshot = %{"ground_station_ref" => station}

    attrs =
      c.reservation
      |> Map.from_struct()
      |> Map.merge(%{
        provider_reservation_id: "impact-#{n}",
        provider_contact_ref: nil,
        idempotency_key: "impact-key-#{n}",
        scheduled_contact_id: "impact-schedule-#{n}",
        spacecraft_id: Keyword.get(opts, :spacecraft_id, c.reservation.spacecraft_id),
        lifecycle_state: Keyword.get(opts, :state, :confirmed),
        starts_at: at(starts),
        ends_at: at(starts + 10),
        requested_snapshot_document: snapshot,
        provider_confirmed_snapshot_document: snapshot,
        cadence_accepted_snapshot_document: snapshot
      })

    {:ok, reservation} = ProviderReservations.create_attempt(c.organization_id, attrs)
    reservation
  end

  test "lists live passes at the station that overlap the window", %{c: c, alice: alice} do
    reserve!(c, 1, "svb", 30, spacecraft_id: "sat-a")
    reserve!(c, 2, "svb", 60, spacecraft_id: "sat-b")
    reserve!(c, 3, "trl", 45)
    reserve!(c, 4, "svb", 50, state: :canceled)
    reserve!(c, 5, "svb", 300)

    assert {:ok, impact} = StationImpact.impact(alice, c.mission_id, "svb", at(25), at(65))

    assert %{passes_hit: 2, truncated: false, ground_station_id: "svb"} = impact
    assert Enum.sort(impact.reservation_ids) == ["impact-1", "impact-2"]
    assert Enum.sort(impact.spacecraft_ids) == ["sat-a", "sat-b"]
    # Direct bookings carry no plan; plan-bound ones add {id, version} here (for K2 → S8).
    assert impact.plans == []

    # reserve!(c, 4, …, state: :canceled) at svb in the window: already lost.
    assert %{count: 1, reservation_ids: ["impact-4"], plans: []} = impact.lost
  end

  test "a station with nothing booked reports no hits", %{c: c, alice: alice} do
    assert {:ok, %{passes_hit: 0, reservation_ids: []}} =
             StationImpact.impact(alice, c.mission_id, "svb", at(0), at(600))
  end

  test "outsiders can't read impact", %{c: c} do
    outsider =
      member_scope(c.organization_id, :member, "Eve") |> Map.put(:organization_membership, nil)

    assert {:error, :forbidden} =
             StationImpact.impact(outsider, c.mission_id, "svb", at(0), at(60))
  end
end
