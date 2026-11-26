defmodule Cadence.Telemetry.Storage.QuestDB.SeedLatestOnMeasureTest do
  @moduledoc """
  A MEASUREMENT, not a feature test (#831): what seeding a starting partition's current values from
  QuestDB would cost: one `LATEST ON observed_at PARTITION BY point_id` per spacecraft. It writes
  N spacecraft x P points x R rows, then times that query for single spacecraft and prints the
  figures (CI's questdb-integration job log). It asserts only that the query returns every point.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.QuestDBCase

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.{RestClient, SQL}

  @moduletag :questdb
  @moduletag timeout: 900_000

  setup :setup_questdb

  @points 200
  @rows_per_point 10

  test "LATEST ON observed_at PARTITION BY point_id for one spacecraft, at growing table sizes" do
    mission = "mission-seed-measure-#{System.unique_integer([:positive])}"
    now = DateTime.utc_now()

    for crafts <- [25, 100, 200] do
      write_craft_range!(mission, now, crafts)
      total = crafts * @points * @rows_per_point
      wait_for_rows(mission, total)

      timings =
        for n <- Enum.take_random(1..crafts, 15) do
          {micros, {:ok, %{"dataset" => rows}}} =
            :timer.tc(fn -> RestClient.exec(latest_on(mission, "sc-#{n}"), []) end)

          assert length(rows) == @points
          micros / 1_000
        end

      sorted = Enum.sort(timings)

      IO.puts(
        "QUESTDB SEED MEASURE: table #{total} rows (#{crafts} spacecraft x #{@points} points x " <>
          "#{@rows_per_point} rows): LATEST ON for one spacecraft p50 " <>
          "#{Float.round(Enum.at(sorted, 7), 1)} ms, max #{Float.round(List.last(sorted), 1)} ms"
      )
    end
  end

  defp latest_on(mission, spacecraft) do
    """
    SELECT point_id, observed_at, receipt_time, engineering_value
    FROM telemetry_observations
    WHERE mission_id = #{SQL.literal(mission)} AND spacecraft_id = #{SQL.literal(spacecraft)}
      AND realm = 'flight'
    LATEST ON observed_at PARTITION BY point_id
    """
  end

  # Writes spacecraft 1..crafts (those not yet written), `@rows_per_point` rows per point.
  defp write_craft_range!(mission, now, crafts) do
    written = Process.get(:written, 0)

    for n <- (written + 1)..crafts//1, chunk <- craft_envelopes(mission, now, n) do
      write_observations!(chunk)
    end

    Process.put(:written, crafts)
  end

  defp craft_envelopes(mission, now, n) do
    for p <- 1..@points, r <- 1..@rows_per_point do
      at = DateTime.add(now, -(@rows_per_point - r) * 6 - rem(p, 5), :second)
      envelope(mission, "sc-#{n}", "HK.p#{p}", "#{n}-#{p}-#{r}", at, r)
    end
    |> Enum.chunk_every(2_000)
  end

  defp wait_for_rows(mission, total) do
    read_back(
      fn ->
        {:ok, %{"dataset" => [[count]]}} =
          RestClient.exec(
            "SELECT count() FROM telemetry_observations WHERE mission_id = #{SQL.literal(mission)}",
            []
          )

        if count >= total, do: {:ok, count}, else: count
      end,
      300_000
    )
  end

  defp envelope(mission, craft, point, id, at, value) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-seed-measure",
        mission_id: mission,
        realm: :flight,
        data_source_id: "ds-seed-measure",
        binding_id: "binding-seed-measure",
        source_endpoint_id: "station-seed-measure",
        recorded_at: at,
        metadata: %{}
      )

    sample = %Sample{
      sample_id: "seed-#{id}",
      mission_id: mission,
      spacecraft_id: craft,
      point_id: point,
      point_name: point,
      packet_definition_id: "pd-seed",
      packet_definition_version: 1,
      packet_id: "packet-#{id}",
      evidence_id: "evidence-#{id}",
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: at,
      receipt_time: at,
      provenance: %{}
    }

    {:ok, envelope} = ObservationEnvelope.from_sample(context, sample, validity_state: :canonical)
    envelope
  end
end
