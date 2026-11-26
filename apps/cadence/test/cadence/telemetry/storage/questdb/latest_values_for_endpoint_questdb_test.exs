defmodule Cadence.Telemetry.Storage.QuestDB.LatestValuesForEndpointTest do
  @moduledoc """
  The statement a starting partition seeds its current values with (#831), against a real QuestDB:
  the newest canonical flight value of every (spacecraft, point) one source endpoint wrote, and
  nothing of another endpoint's, another mission's, or an older row.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.QuestDBCase

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, RestClient, SQL}

  @moduletag :questdb

  setup :setup_questdb

  test "returns the newest value per spacecraft and point for one source endpoint" do
    mission = "mission-latest-#{System.unique_integer([:positive])}"
    now = DateTime.utc_now()
    ago = fn seconds -> DateTime.add(now, -seconds, :second) end

    write_observations!([
      envelope(mission, "station-1", "sc-1", "HK.a", "a1", ago.(30), 1.0),
      envelope(mission, "station-1", "sc-1", "HK.a", "a2", ago.(10), 2.0),
      envelope(mission, "station-1", "sc-1", "HK.b", "b1", ago.(20), 3.0),
      envelope(mission, "station-1", "sc-2", "HK.a", "c1", ago.(5), 4.0),
      envelope(mission, "station-2", "sc-3", "HK.a", "d1", ago.(5), 5.0)
    ])

    wait_for_rows(mission, 5)

    assert {:ok, samples} = ObservationReader.latest_values_for_endpoint(mission, "station-1")

    assert samples |> Map.new(&{{&1.spacecraft_id, &1.point_id}, &1.engineering_value}) == %{
             {"sc-1", "HK.a"} => 2.0,
             {"sc-1", "HK.b"} => 3.0,
             {"sc-2", "HK.a"} => 4.0
           }

    assert {:ok, []} = ObservationReader.latest_values_for_endpoint(mission, "station-none")
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
      60_000
    )
  end

  defp envelope(mission, endpoint, craft, point, id, at, value) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-latest",
        mission_id: mission,
        realm: :flight,
        data_source_id: "ds-latest",
        binding_id: "binding-latest",
        source_endpoint_id: endpoint,
        recorded_at: at,
        metadata: %{}
      )

    sample = %Sample{
      sample_id: "latest-#{id}",
      mission_id: mission,
      spacecraft_id: craft,
      point_id: point,
      point_name: point,
      packet_definition_id: "pd-latest",
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
