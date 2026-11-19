defmodule Cadence.Reads.OffPlanBookingEventsTest do
  use ExUnit.Case, async: true

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.OffPlanBookingEvents

  defp entry(booked_at, starts_at, note) do
    Entry.new(%{
      mission_id: "m",
      source_record_kind: :off_plan_booking,
      source_record_id: "r",
      occurred_at: booked_at,
      category: :transport,
      kind: :contact_booked_off_plan,
      title: "Booked outside a plan",
      metadata: %{
        "spacecraft_name" => "EARENDIL-312",
        "station_code" => "SVA",
        "starts_at" => DateTime.to_iso8601(starts_at),
        "note" => note
      }
    })
  end

  test "the AOS is dated when it isn't on the booking's UTC day (ux)" do
    later = entry(~U[2026-11-13 10:20:00Z], ~U[2026-11-15 03:10:00Z], nil)
    same = entry(~U[2026-11-13 10:20:00Z], ~U[2026-11-13 23:10:00Z], nil)

    assert OffPlanBookingEvents.sentence(later, " by Mira K.") ==
             "EARENDIL-312 · SVA 11-15 03:10Z booked outside a plan by Mira K."

    assert OffPlanBookingEvents.sentence(same, "") ==
             "EARENDIL-312 · SVA 23:10Z booked outside a plan by an operator"
  end

  test "the detail quotes the note, then says it doesn't count" do
    assert OffPlanBookingEvents.detail(
             entry(~U[2026-11-13 10:20:00Z], ~U[2026-11-15 03:10:00Z], "Eclipse")
           ) ==
             "“Eclipse” Doesn't count toward contact rules."

    assert OffPlanBookingEvents.detail(
             entry(~U[2026-11-13 10:20:00Z], ~U[2026-11-15 03:10:00Z], nil)
           ) ==
             "Doesn't count toward contact rules."
  end
end
