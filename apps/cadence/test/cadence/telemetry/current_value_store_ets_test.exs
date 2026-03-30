defmodule Cadence.Telemetry.CurrentValueStoreETSTest do
  use ExUnit.Case, async: false

  alias Cadence.Telemetry.CurrentValueStore.ETS
  alias Cadence.Telemetry.Sample

  setup do
    start_supervised!(ETS)
    ETS.reset()
    :ok
  end

  test "keeps the newest sample per mission scope and point" do
    newer_sample =
      sample("sample-new", "mission-ets", "HK.counter", 20, DateTime.from_unix!(1_700_000_200))

    older_sample =
      sample("sample-old", "mission-ets", "HK.counter", 10, DateTime.from_unix!(1_700_000_100))

    assert :ok = ETS.record_samples([newer_sample, older_sample])

    assert ETS.latest_value("mission-ets", "HK.counter", []).raw_value == 20
    assert [latest_sample] = ETS.latest_values_for_mission("mission-ets", [])
    assert latest_sample.sample_id == "sample-new"
  end

  test "separates mission scope values from spacecraft scope values" do
    mission_sample =
      sample(
        "sample-mission",
        "mission-ets",
        "HK.counter",
        1,
        DateTime.from_unix!(1_700_000_100)
      )

    spacecraft_sample =
      sample(
        "sample-spacecraft",
        "mission-ets",
        "HK.counter",
        2,
        DateTime.from_unix!(1_700_000_200),
        spacecraft_id: "sc-001"
      )

    assert :ok = ETS.record_samples([mission_sample, spacecraft_sample])

    assert ETS.latest_value("mission-ets", "HK.counter", []).raw_value == 1
    assert ETS.latest_value("mission-ets", "HK.counter", spacecraft_id: "sc-001").raw_value == 2
  end

  defp sample(sample_id, mission_id, point_id, raw_value, receipt_time, opts \\ []) do
    %Sample{
      sample_id: sample_id,
      mission_id: mission_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      receipt_time: receipt_time,
      generation_time: receipt_time,
      provenance: %{}
    }
  end
end
