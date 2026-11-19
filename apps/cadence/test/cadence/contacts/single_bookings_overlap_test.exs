defmodule Cadence.Contacts.SingleBookingsOverlapTest do
  @moduledoc "Book a pass: which live booking an offer overlaps, and why (DECISIONS #78)."
  use ExUnit.Case, async: true

  alias Cadence.Contacts.SingleBookings

  @t ~U[2026-11-15 10:00:00Z]

  defp slot(spacecraft, antenna, from_min, to_min),
    do: %{
      spacecraft_id: spacecraft,
      antenna_ref: antenna,
      starts_at: DateTime.add(@t, from_min * 60),
      ends_at: DateTime.add(@t, to_min * 60)
    }

  defp booked(id, spacecraft, antenna, from_min, to_min),
    do:
      slot(spacecraft, antenna, from_min, to_min)
      |> Map.merge(%{
        reservation_id: id,
        spacecraft_name: String.upcase(spacecraft),
        station_code: "SVA",
        off_plan: true
      })

  test "the same spacecraft overlapping comes first, then another spacecraft on the same antenna" do
    occupancy = [booked("r-ant", "sc-2", "ant-1", 0, 10), booked("r-own", "sc-1", "ant-9", 5, 15)]

    assert %{reservation_id: "r-own", reason: "same_spacecraft", spacecraft: %{name: "SC-1"}} =
             SingleBookings.overlap(occupancy, slot("sc-1", "ant-1", 8, 12))

    assert %{reservation_id: "r-ant", reason: "same_antenna", station_code: "SVA"} =
             SingleBookings.overlap(occupancy, slot("sc-1", "ant-1", 0, 4))
  end

  test "an opportunity two routes reach is offered once, through the first route" do
    route = fn key, provider ->
      %{
        route_key: key,
        provider_id: provider,
        provider_display_name: provider,
        route_display_name: key
      }
    end

    offer = fn id -> %{"id" => id, "starts_at" => "2026-11-15T10:00:00Z"} end

    found = [
      {route.("b-route", "prov-1"), offer.("opp-1")},
      {route.("a-route", "prov-1"), offer.("opp-1")},
      {route.("a-route", "prov-1"), offer.("opp-2")},
      {route.("a-route", "prov-2"), offer.("opp-1")}
    ]

    assert [
             {%{route_key: "a-route", provider_id: "prov-1"}, %{"id" => "opp-1"}},
             {%{route_key: "a-route", provider_id: "prov-1"}, %{"id" => "opp-2"}},
             {%{route_key: "a-route", provider_id: "prov-2"}, %{"id" => "opp-1"}}
           ] = SingleBookings.Search.distinct_offers(found)
  end

  test "touching ends, another antenna, or no antenna is free" do
    occupancy = [booked("r", "sc-2", "ant-1", 0, 10)]

    assert SingleBookings.overlap(occupancy, slot("sc-1", "ant-1", 10, 20)) == nil
    assert SingleBookings.overlap(occupancy, slot("sc-1", "ant-2", 0, 10)) == nil
    assert SingleBookings.overlap(occupancy, slot("sc-1", nil, 0, 10)) == nil
  end
end
