defmodule CadenceWeb.Console.ContactWindowScaleAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Persistence.JsonDocument
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow
  alias CadenceWeb.TestFixtures

  setup do
    fixture = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, fixture.organization, role: :organization_admin)

    {:ok, station} =
      GroundStationStore.persist_ground_station(
        fixture.organization_id,
        GroundStation.new(%{
          ground_station_id: "ground-station-fleet",
          mission_id: fixture.mission_id,
          display_name: "Fleet test station",
          code: "FLEET"
        })
      )

    starts_at = DateTime.utc_now() |> DateTime.add(7 * 86_400) |> DateTime.truncate(:second)
    starts_at = DateTime.from_unix!(DateTime.to_unix(starts_at, :microsecond), :microsecond)
    spacecraft_ids = Enum.map(1..1_000, &spacecraft_id/1)
    insert_spacecraft(fixture, spacecraft_ids, starts_at)
    insert_bookings(fixture, station, spacecraft_ids, starts_at)

    %{
      user: user,
      base: "/api/v1/missions/#{fixture.mission_id}",
      from: DateTime.add(starts_at, -1_800),
      to: DateTime.add(starts_at, 21_600),
      starts_at: starts_at,
      station: station,
      spacecraft_ids: spacecraft_ids
    }
  end

  test "passes page all 1,000 spacecraft across tied start times and SQL filters", c do
    params = %{"station" => "FLEET", "states" => "confirmed", "limit" => 137}

    counts = %{
      "total" => 1_000,
      "booked" => 1_000,
      "hand_started" => 0,
      "in_contact" => 0,
      "upcoming" => 1_000,
      "synthetic" => 1
    }

    rows = collect(c, "/passes", "passes", params, counts)
    assert Enum.map(rows, & &1["spacecraft_id"]) == c.spacecraft_ids

    descending = collect(c, "/passes", "passes", Map.put(params, "order", "desc"), counts)
    assert Enum.map(descending, & &1["spacecraft_id"]) == Enum.reverse(c.spacecraft_ids)

    assert %{"meta" => %{"next_cursor" => cursor}} = get_page(c, "/passes", params)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"cursor" => _}}} =
             get_page(
               c,
               "/passes",
               Map.merge(params, %{"cursor" => cursor, "order" => "desc"}),
               422
             )
  end

  test "contact findings page every conflict and gap across the same 1,000 spacecraft", c do
    c.user
    |> TestFixtures.member_conn()
    |> post(c.base <> "/station-availability/#{c.station.ground_station_id}/windows", %{
      "kind" => "outage",
      "starts_at" => DateTime.to_iso8601(c.starts_at),
      "ends_at" => DateTime.to_iso8601(DateTime.add(c.starts_at, 60))
    })
    |> json_response(201)

    params = %{"limit" => 401}

    rows =
      collect(c, "/contact-findings", "findings", params, %{"conflicts" => 1_998, "gaps" => 1_000})

    assert Enum.frequencies_by(rows, & &1["kind"]) == %{
             "booked_into_outage" => 1_000,
             "station_double_booked" => 998,
             "coverage_gap" => 1_000
           }

    assert Enum.map(Enum.filter(rows, &(&1["kind"] == "coverage_gap")), & &1["spacecraft"]["id"]) ==
             c.spacecraft_ids

    assert %{"overlap_s" => 600, "message" => message} =
             Enum.find(rows, &(&1["kind"] == "station_double_booked"))

    assert message == "fleet-0001 and fleet-0002 overlap by 10 minutes at FLEET."
    assert %{"severity" => "critical"} = Enum.find(rows, &(&1["kind"] == "booked_into_outage"))

    assert %{"meta" => %{"next_cursor" => cursor}} = get_page(c, "/contact-findings", params)

    assert %{"error" => %{"details" => %{"cursor" => _}}} =
             get_page(
               c,
               "/contact-findings",
               Map.merge(params, %{"cursor" => cursor, "max_gap_s" => 600}),
               422
             )
  end

  test "a prior live booking anchors a gap that crosses the start of the window", c do
    data = get_page(c, "/contact-findings", %{"max_gap_s" => 2_000, "limit" => 1})["data"]
    craft_id = hd(c.spacecraft_ids)

    assert [
             %{
               "kind" => "coverage_gap",
               "spacecraft" => %{"id" => ^craft_id},
               "gap" => %{"from" => from, "to" => to, "seconds" => 2_400}
             }
           ] = data["findings"]

    assert {:ok, at, 0} = DateTime.from_iso8601(from)
    assert DateTime.diff(c.from, at) == 600
    assert {:ok, at, 0} = DateTime.from_iso8601(to)
    assert DateTime.compare(c.starts_at, at) == :eq
    assert data["counts"]["gaps"] == 1_001
  end

  test "station impact counts a spacecraft once across live and lost bookings", c do
    data = get_page(c, "/station-availability/#{c.station.ground_station_id}/impact", %{})["data"]

    assert %{"spacecraft_count" => 1_000, "passes_hit" => 1_000, "lost" => %{"count" => 1}} = data
    assert data["lost"]["spacecraft_ids"] == [hd(c.spacecraft_ids)]
  end

  test "Now counts distinct live spacecraft and only confirmed or active future bookings", c do
    [first, second, third | _] = c.spacecraft_ids
    base = Repo.get!(ProviderReservationRow, "booking-#{first}")
    base = Map.take(base, ProviderReservationRow.__schema__(:fields))
    station = c.station.ground_station_id
    now = DateTime.utc_now()
    past = DateTime.add(now, -60)
    future = DateTime.add(now, 120)

    rows = [
      row(base, "active-now", first, station, past, "active", false),
      %{row(base, "pass-now", first, station, past, "confirmed", false) | pass_phase: "pass"},
      %{row(base, "lost-now", second, station, past, "failed", false) | pass_phase: "pass"},
      row(base, "confirmed-future", second, station, future, "confirmed", true),
      row(base, "active-future", first, station, future, "active", false),
      row(base, "pending-future", third, station, future, "pending", false)
    ]

    Repo.insert_all(ProviderReservationRow, rows)

    result =
      get_page(c, "/passes", %{
        "from" => DateTime.to_iso8601(DateTime.add(now, -120)),
        "to" => DateTime.to_iso8601(DateTime.add(now, 300)),
        "station" => "FLEET",
        "limit" => 1
      })

    assert %{
             "total" => 6,
             "booked" => 6,
             "hand_started" => 0,
             "in_contact" => 1,
             "upcoming" => 2,
             "synthetic" => 1
           } = result["data"]["counts"]
  end

  defp insert_spacecraft(fixture, ids, now) do
    ids
    |> Enum.map(
      &%{
        spacecraft_id: &1,
        organization_id: fixture.organization_id,
        mission_id: fixture.mission_id,
        display_name: &1,
        lifecycle_state: "active",
        metadata: %{},
        inserted_at: now
      }
    )
    |> Enum.chunk_every(250)
    |> Enum.each(&Repo.insert_all(SpacecraftRow, &1))
  end

  defp insert_bookings(fixture, station, ids, starts_at) do
    base = Repo.get!(ProviderReservationRow, fixture.reservation.provider_reservation_id)
    base = Map.take(base, ProviderReservationRow.__schema__(:fields))
    synthetic_id = List.last(ids)

    rows =
      for id <- ids do
        row(
          base,
          "booking-#{id}",
          id,
          station.ground_station_id,
          starts_at,
          "confirmed",
          id == synthetic_id
        )
      end

    [first | _] = ids

    [
      row(
        base,
        "previous-pass",
        first,
        "unmatched-station",
        DateTime.add(starts_at, -3_000),
        "confirmed",
        false
      ),
      row(base, "other-station", first, "unmatched-station", starts_at, "confirmed", false),
      row(base, "lost-at-station", first, station.ground_station_id, starts_at, "canceled", false)
      | rows
    ]
    |> Enum.chunk_every(200)
    |> Enum.each(&Repo.insert_all(ProviderReservationRow, &1))
  end

  defp row(base, id, spacecraft_id, station_id, starts_at, state, synthetic) do
    antenna = if synthetic, do: "b", else: "a"

    snapshot =
      JsonDocument.wrap_value(%{
        "ground_station_ref" => station_id,
        "antenna_or_service_pool_ref" => antenna,
        "synthetic" => synthetic
      })

    Map.merge(base, %{
      provider_reservation_id: id,
      provider_contact_ref: id,
      scheduled_contact_id: "scheduled-#{id}",
      idempotency_key: id,
      lifecycle_state: state,
      spacecraft_id: spacecraft_id,
      provider_spacecraft_ref: spacecraft_id,
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 600),
      provider_confirmed_snapshot_document: snapshot,
      cadence_accepted_snapshot_document: snapshot
    })
  end

  defp spacecraft_id(n), do: "fleet-" <> String.pad_leading(Integer.to_string(n), 4, "0")

  defp collect(c, path, key, params, counts) do
    {cursor, batches} =
      Enum.reduce_while(1..12, {nil, []}, fn _, {cursor, batches} ->
        params = if cursor, do: Map.put(params, "cursor", cursor), else: params
        body = get_page(c, path, params)
        cursor = body["meta"]["next_cursor"]
        data = body["data"]
        assert data["counts"] == counts
        assert data["truncated"] == is_binary(cursor)
        batches = [data[key] | batches]
        if cursor, do: {:cont, {cursor, batches}}, else: {:halt, {nil, batches}}
      end)

    assert cursor == nil
    rows = batches |> Enum.reverse() |> List.flatten()
    ids = Enum.map(rows, & &1["id"])
    assert length(ids) == MapSet.size(MapSet.new(ids))
    rows
  end

  defp get_page(c, path, params, status \\ 200) do
    params =
      Map.merge(
        %{"from" => DateTime.to_iso8601(c.from), "to" => DateTime.to_iso8601(c.to)},
        params
      )

    c.user
    |> TestFixtures.member_conn()
    |> get(c.base <> path <> "?" <> URI.encode_query(params))
    |> json_response(status)
  end
end
