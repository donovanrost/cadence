defmodule Cadence.Telemetry.CurrentValueStoreETSTest do
  use Cadence.UnitCase, async: false

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

  test "does not replace current state with a late-arriving older source-time sample" do
    current_sample =
      sample("sample-current", "mission-ets", "HK.counter", 20, ~U[2026-06-21 12:10:05Z],
        generation_time: ~U[2026-06-21 12:10:00Z]
      )

    late_arrival =
      sample("sample-late", "mission-ets", "HK.counter", 10, ~U[2026-06-21 12:15:00Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    assert :ok = ETS.record_samples([current_sample])
    assert :ok = ETS.record_samples([late_arrival])

    latest_sample = ETS.latest_value("mission-ets", "HK.counter", [])
    assert latest_sample.sample_id == "sample-current"
    assert latest_sample.raw_value == 20
  end

  test "does not replace canonical current state with unresolved conflicts" do
    canonical =
      sample("sample-canonical", "mission-ets", "HK.counter", 20, ~U[2026-06-21 12:10:00Z],
        validity_state: :canonical
      )

    conflict =
      sample("sample-conflict", "mission-ets", "HK.counter", 99, ~U[2026-06-21 12:11:00Z],
        validity_state: :conflict
      )

    assert :ok = ETS.record_samples([canonical])
    assert :ok = ETS.record_samples([conflict])

    latest_sample = ETS.latest_value("mission-ets", "HK.counter", [])
    assert latest_sample.sample_id == "sample-canonical"
    assert latest_sample.raw_value == 20

    assert [] =
             ETS.latest_values_for_mission("mission-ets", validity_state: :conflict)
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

  test "separates current values by storage source context" do
    flight_sample =
      sample("sample-flight", "mission-ets", "HK.counter", 1, ~U[2026-06-21 12:00:00Z],
        realm: :flight,
        data_source_id: "flight-questdb",
        binding_id: "flight-binding"
      )

    rehearsal_sample =
      sample("sample-rehearsal", "mission-ets", "HK.counter", 2, ~U[2026-06-21 12:01:00Z],
        realm: :rehearsal,
        data_source_id: "rehearsal-questdb",
        binding_id: "rehearsal-binding"
      )

    assert :ok = ETS.record_samples([flight_sample, rehearsal_sample])

    assert ETS.latest_value("mission-ets", "HK.counter",
             realm: :flight,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-binding"
           ).raw_value == 1

    assert ETS.latest_value("mission-ets", "HK.counter",
             realm: :rehearsal,
             data_source_id: "rehearsal-questdb",
             source_binding_id: "rehearsal-binding"
           ).raw_value == 2

    assert [] =
             ETS.latest_values_for_mission("mission-ets",
               realm: :rehearsal,
               data_source_id: "flight-questdb"
             )
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
      generation_time: Keyword.get(opts, :generation_time, receipt_time),
      provenance: provenance(opts)
    }
  end

  defp provenance(opts) do
    storage =
      %{}
      |> maybe_put("validity_state", atom_text(Keyword.get(opts, :validity_state)))
      |> maybe_put("realm", atom_text(Keyword.get(opts, :realm)))
      |> maybe_put("data_source_id", Keyword.get(opts, :data_source_id))
      |> maybe_put("binding_id", Keyword.get(opts, :binding_id))

    if map_size(storage) == 0 do
      %{}
    else
      %{"storage" => storage}
    end
  end

  defp atom_text(nil), do: nil
  defp atom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_text(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
