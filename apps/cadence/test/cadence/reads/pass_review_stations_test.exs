defmodule Cadence.Reads.PassReviewStationsTest do
  @moduledoc "Station identity in pass review resolves by id, code or provider ref (as /passes)."
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures
  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.Contacts.PassResults.Row
  alias Cadence.Reads.PassReview

  setup do
    c = CommandReviewFixtures.scope!()

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        c.org,
        GroundStation.new(%{
          ground_station_id: "gs-svb",
          mission_id: c.mission,
          display_name: "Svalbard 1",
          code: "SVB1"
        })
      )

    c
  end

  defp result!(c, id, ref, aos, outcome \\ "missed") do
    %Row{}
    |> Row.changeset(%{
      provider_reservation_id: id,
      organization_id: c.org,
      mission_id: c.mission,
      provider_id: "provider-test",
      spacecraft_id: "sc-1",
      ground_station_ref: ref,
      planned_aos: aos,
      planned_los: DateTime.add(aos, 600),
      planned_seconds: 600,
      outcome: outcome,
      cause: "no_acquisition",
      cause_source: "provider",
      owner: "provider"
    })
    |> Repo.insert!()
  end

  test "a code ref resolves, and the same station by id and by code is one by_station row", c do
    t0 = ~U[2026-11-10 01:00:00.000000Z]
    result!(c, "res-by-code", "SVB1", t0)
    result!(c, "res-by-id", "gs-svb", DateTime.add(t0, 3_600))
    result!(c, "res-unknown", "PUQ", DateTime.add(t0, 7_200))

    from = DateTime.add(t0, -60)
    to = DateTime.add(t0, 86_400)

    {:ok, %{rows: rows}} = PassReview.rows(c.scope, c.mission, from, to, %{})
    by_id = Map.new(rows, &{&1.id, &1.station})

    # The ref stays raw; identity is filled from the matched station.
    assert by_id["res-by-code"] == %{ref: "SVB1", id: "gs-svb", code: "SVB1", name: "Svalbard 1"}
    assert by_id["res-by-id"] == %{ref: "gs-svb", id: "gs-svb", code: "SVB1", name: "Svalbard 1"}
    assert by_id["res-unknown"] == %{ref: "PUQ", id: nil, code: nil, name: "PUQ"}

    {:ok, summary} = PassReview.summary(c.scope, c.mission, from, to)

    assert [svb] = Enum.filter(summary.by_station, &(&1.station.id == "gs-svb"))
    assert %{planned: 2, missed: 2, station: %{code: "SVB1", name: "Svalbard 1"}} = svb

    assert [%{planned: 1, station: %{ref: "PUQ"}}] =
             Enum.filter(summary.by_station, &is_nil(&1.station.id))
  end

  # contacts.md R1: missed includes failed, and failed is also given alone.
  test "a by_station row's exact shape, with failed counted alone and within missed", c do
    t0 = ~U[2026-11-10 01:00:00.000000Z]
    result!(c, "res-missed", "gs-svb", t0)
    result!(c, "res-failed", "gs-svb", DateTime.add(t0, 3_600), "failed")

    {:ok, summary} =
      PassReview.summary(c.scope, c.mission, DateTime.add(t0, -60), DateTime.add(t0, 86_400))

    assert [row] = summary.by_station

    assert Map.delete(row, :provider) == %{
             station: %{ref: "gs-svb", id: "gs-svb", code: "SVB1", name: "Svalbard 1"},
             planned: 2,
             realized: 0,
             partial: 0,
             missed: 2,
             failed: 1,
             canceled: 0,
             planned_seconds: 1200,
             flown_seconds: 0
           }

    assert Map.has_key?(row, :provider)
  end
end
