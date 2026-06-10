defmodule Cadence.Telemetry.HistoryStoreETSTest do
  use ExUnit.Case, async: false

  alias Cadence.Telemetry.HistoryStore.ETS
  alias Cadence.Telemetry.Sample

  setup do
    previous_config = Application.get_env(:cadence, :telemetry_history_store, [])

    Application.put_env(:cadence, :telemetry_history_store,
      module: ETS,
      max_samples_per_point: :infinity
    )

    start_supervised!(ETS)
    ETS.reset()

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_history_store, previous_config)
    end)

    :ok
  end

  test "returns point history in requested time order" do
    first = sample("sample-1", "mission-ets", "HK.counter", 10, 1_700_000_100)
    second = sample("sample-2", "mission-ets", "HK.counter", 20, 1_700_000_200)

    assert :ok = ETS.persist_samples([second, first])

    assert ["sample-1", "sample-2"] =
             ETS.sample_history("mission-ets", "HK.counter", order: :asc, limit: 10)
             |> Enum.map(& &1.sample_id)

    assert ["sample-2", "sample-1"] =
             ETS.sample_history("mission-ets", "HK.counter", order: :desc, limit: 10)
             |> Enum.map(& &1.sample_id)
  end

  test "separates mission history from spacecraft-scoped history" do
    mission_sample = sample("sample-mission", "mission-ets", "HK.counter", 1, 1_700_000_100)

    spacecraft_sample =
      sample("sample-spacecraft", "mission-ets", "HK.counter", 2, 1_700_000_200,
        spacecraft_id: "sc-001"
      )

    assert :ok = ETS.persist_samples([mission_sample, spacecraft_sample])

    assert [1, 2] =
             ETS.sample_history("mission-ets", "HK.counter", order: :asc)
             |> Enum.map(& &1.raw_value)

    assert [2] =
             ETS.sample_history("mission-ets", "HK.counter",
               spacecraft_id: "sc-001",
               order: :asc
             )
             |> Enum.map(& &1.raw_value)
  end

  test "filters by receipt time window" do
    assert :ok =
             ETS.persist_samples([
               sample("sample-1", "mission-ets", "HK.counter", 10, 1_700_000_100),
               sample("sample-2", "mission-ets", "HK.counter", 20, 1_700_000_200),
               sample("sample-3", "mission-ets", "HK.counter", 30, 1_700_000_300)
             ])

    history =
      ETS.sample_history("mission-ets", "HK.counter",
        from_receipt_time: DateTime.from_unix!(1_700_000_150),
        to_receipt_time: DateTime.from_unix!(1_700_000_250),
        order: :asc,
        limit: 10
      )

    assert Enum.map(history, & &1.raw_value) == [20]
  end

  test "bounds retained samples per mission scope and point" do
    Application.put_env(:cadence, :telemetry_history_store,
      module: ETS,
      max_samples_per_point: 2
    )

    assert :ok =
             ETS.persist_samples([
               sample("sample-1", "mission-ets", "HK.counter", 10, 1_700_000_100),
               sample("sample-2", "mission-ets", "HK.counter", 20, 1_700_000_200),
               sample("sample-3", "mission-ets", "HK.counter", 30, 1_700_000_300)
             ])

    history = ETS.sample_history("mission-ets", "HK.counter", order: :asc, limit: 10)

    assert Enum.map(history, & &1.sample_id) == ["sample-2", "sample-3"]
  end

  defp sample(sample_id, mission_id, point_id, raw_value, receipt_unix, opts \\ []) do
    receipt_time = DateTime.from_unix!(receipt_unix)

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
