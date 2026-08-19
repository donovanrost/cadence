defmodule Cadence.Telemetry.HistoryStoreETSTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Telemetry.HistoryStore.ETS
  alias Cadence.Telemetry.Sample

  setup do
    start_supervised!({ETS, max_samples_per_point: :infinity})
    ETS.reset()

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

  test "filters by observed source time window" do
    assert :ok =
             ETS.persist_samples([
               sample("sample-1", "mission-ets", "HK.counter", 10, 1_700_000_100,
                 generation_unix: 1_700_000_010
               ),
               sample("sample-2", "mission-ets", "HK.counter", 20, 1_700_000_200,
                 generation_unix: 1_700_000_020
               ),
               sample("sample-3", "mission-ets", "HK.counter", 30, 1_700_000_300,
                 generation_unix: 1_700_000_030
               )
             ])

    history =
      ETS.sample_history("mission-ets", "HK.counter",
        from_observed_at: DateTime.from_unix!(1_700_000_015),
        to_observed_at: DateTime.from_unix!(1_700_000_025),
        order: :asc,
        limit: 10
      )

    assert Enum.map(history, & &1.raw_value) == [20]
  end

  test "orders generation-time history by observed source time" do
    assert :ok =
             ETS.persist_samples([
               sample("sample-late-receipt", "mission-ets", "HK.counter", 30, 1_700_000_300,
                 generation_unix: 1_700_000_010
               ),
               sample("sample-early-receipt", "mission-ets", "HK.counter", 20, 1_700_000_100,
                 generation_unix: 1_700_000_020
               )
             ])

    assert ["sample-late-receipt", "sample-early-receipt"] =
             ETS.sample_history("mission-ets", "HK.counter",
               time_axis: :generation_time,
               from_observed_at: DateTime.from_unix!(1_700_000_005),
               to_observed_at: DateTime.from_unix!(1_700_000_025),
               order: :asc,
               limit: 10
             )
             |> Enum.map(& &1.sample_id)
  end

  test "filters history by storage source context" do
    assert :ok =
             ETS.persist_samples([
               sample("sample-flight", "mission-ets", "HK.counter", 10, 1_700_000_100,
                 realm: :flight,
                 data_source_id: "flight-questdb",
                 binding_id: "flight-binding"
               ),
               sample("sample-rehearsal", "mission-ets", "HK.counter", 20, 1_700_000_200,
                 realm: :rehearsal,
                 data_source_id: "rehearsal-questdb",
                 binding_id: "rehearsal-binding"
               )
             ])

    history =
      ETS.sample_history("mission-ets", "HK.counter",
        realm: :rehearsal,
        data_source_id: "rehearsal-questdb",
        source_binding_id: "rehearsal-binding",
        order: :asc,
        limit: 10
      )

    assert Enum.map(history, & &1.sample_id) == ["sample-rehearsal"]

    assert [] =
             ETS.sample_history("mission-ets", "HK.counter",
               realm: :rehearsal,
               data_source_id: "flight-questdb",
               source_binding_id: "rehearsal-binding",
               order: :asc,
               limit: 10
             )
  end

  test "defaults history reads to canonical-compatible samples" do
    assert :ok =
             ETS.persist_samples([
               sample("sample-canonical", "mission-ets", "HK.counter", 20, 1_700_000_100,
                 validity_state: :canonical
               ),
               sample("sample-conflict", "mission-ets", "HK.counter", 99, 1_700_000_200,
                 validity_state: :conflict
               )
             ])

    assert ["sample-canonical"] =
             ETS.sample_history("mission-ets", "HK.counter", order: :asc, limit: 10)
             |> Enum.map(& &1.sample_id)

    assert ["sample-canonical", "sample-conflict"] =
             ETS.sample_history("mission-ets", "HK.counter",
               view: :all_revisions,
               order: :asc,
               limit: 10
             )
             |> Enum.map(& &1.sample_id)
  end

  test "bounds retained samples per mission scope and point" do
    assert :ok = stop_supervised(ETS)
    start_supervised!({ETS, max_samples_per_point: 2})

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
    generation_time = opts |> Keyword.get(:generation_unix, receipt_unix) |> DateTime.from_unix!()

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
      generation_time: generation_time,
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
