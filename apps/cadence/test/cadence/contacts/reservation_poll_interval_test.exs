defmodule Cadence.Contacts.ReservationPollIntervalTest do
  @moduledoc """
  The reconciler's bands (domain 11-15, api-ops' review): by distance to the pass, and a state
  band for a booking an operator is waiting on, whatever the distance.
  """
  use ExUnit.Case, async: true

  alias Cadence.Contacts.{ProviderReservation, ProviderReservations}

  @now ~U[2026-11-15 12:00:00Z]

  describe "by distance to the pass" do
    test "from AOS − 30 min to LOS: 5 s" do
      assert interval(:confirmed, aos_in: 30 * 60) == 5
      assert interval(:active, aos_in: -60) == 5
    end

    test "AOS within 2 h: 30 s; within 24 h: 60 s; further: 10 min" do
      assert interval(:confirmed, aos_in: 30 * 60 + 1) == 30
      assert interval(:confirmed, aos_in: 2 * 3_600) == 30
      assert interval(:confirmed, aos_in: 2 * 3_600 + 1) == 60
      assert interval(:confirmed, aos_in: 24 * 3_600) == 60
      assert interval(:confirmed, aos_in: 3 * 24 * 3_600) == 600
    end

    test "after LOS, still non-terminal (completing, a provisional failure): 30 s" do
      assert interval(:active, aos_in: -9 * 60) == 30
      assert interval(:failed, aos_in: -9 * 60) == 30
    end
  end

  describe "in flight, whatever the distance (api-ops' condition B)" do
    test "requested, pending or cancel sent: 10 s, even 3 days out" do
      for state <- [:requesting, :pending, :canceling],
          do: assert(interval(state, aos_in: 3 * 24 * 3_600) == 10)
    end

    test "unknown: 30 s" do
      assert interval(:unknown, aos_in: 3 * 24 * 3_600) == 30
    end

    test "a pass already near AOS keeps the faster distance band" do
      assert interval(:pending, aos_in: 60) == 5
    end
  end

  test "a reservation without a window polls every minute" do
    reservation = %ProviderReservation{lifecycle_state: :confirmed, starts_at: nil, ends_at: nil}
    assert ProviderReservations.poll_interval_s(reservation, @now) == 60
  end

  # A pass of 8 min whose AOS is `aos_in` seconds from @now.
  defp interval(state, aos_in: seconds) do
    starts_at = DateTime.add(@now, seconds)

    reservation = %ProviderReservation{
      lifecycle_state: state,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 8 * 60)
    }

    ProviderReservations.poll_interval_s(reservation, @now)
  end
end
