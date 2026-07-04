defmodule Cadence.Telemetry.CurrentValueStorePostgresTest do
  use Cadence.DataCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.Schemas.{PacketRecordRow, RawEvidenceRow}
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Telemetry.CurrentValueStore.Postgres
  alias Cadence.Telemetry.Sample

  setup do
    persist_mission_scope("org-postgres-current", "mission-postgres-current")
    :ok
  end

  test "does not replace current state with a late-arriving older source-time sample" do
    current_sample =
      sample("sample-current", 20, ~U[2026-06-21 12:10:05Z],
        generation_time: ~U[2026-06-21 12:10:00Z]
      )

    late_arrival =
      sample("sample-late", 10, ~U[2026-06-21 12:15:00Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    persist_sample_scope!(current_sample)
    persist_sample_scope!(late_arrival)

    assert :ok = Postgres.record_samples([current_sample])
    assert :ok = Postgres.record_samples([late_arrival])

    latest_sample = Postgres.latest_value("mission-postgres-current", "HK.counter", [])
    assert latest_sample.sample_id == "sample-current"
    assert latest_sample.raw_value == 20
  end

  test "uses receipt time when generation time is missing" do
    older_sample = sample("sample-old", 10, ~U[2026-06-21 12:00:00Z], generation_time: nil)
    newer_sample = sample("sample-new", 20, ~U[2026-06-21 12:00:01Z], generation_time: nil)

    persist_sample_scope!(older_sample)
    persist_sample_scope!(newer_sample)

    assert :ok = Postgres.record_samples([older_sample, newer_sample])

    latest_sample = Postgres.latest_value("mission-postgres-current", "HK.counter", [])
    assert latest_sample.sample_id == "sample-new"
    assert latest_sample.raw_value == 20
  end

  test "does not replace canonical current state with unresolved conflicts" do
    canonical =
      sample("sample-canonical", 20, ~U[2026-06-21 12:10:00Z], validity_state: :canonical)

    conflict =
      sample("sample-conflict", 99, ~U[2026-06-21 12:11:00Z], validity_state: :conflict)

    persist_sample_scope!(canonical)
    persist_sample_scope!(conflict)

    assert :ok = Postgres.record_samples([canonical])
    assert :ok = Postgres.record_samples([conflict])

    latest_sample = Postgres.latest_value("mission-postgres-current", "HK.counter", [])
    assert latest_sample.sample_id == "sample-canonical"
    assert latest_sample.raw_value == 20

    assert [] =
             Postgres.latest_values_for_mission("mission-postgres-current",
               validity_state: :conflict
             )
  end

  test "separates current values by storage source context" do
    flight_sample =
      sample("sample-flight", 1, ~U[2026-06-21 12:00:00Z],
        realm: :flight,
        data_source_id: "flight-questdb",
        binding_id: "flight-binding"
      )

    rehearsal_sample =
      sample("sample-rehearsal", 2, ~U[2026-06-21 12:01:00Z],
        realm: :rehearsal,
        data_source_id: "rehearsal-questdb",
        binding_id: "rehearsal-binding"
      )

    persist_sample_scope!(flight_sample)
    persist_sample_scope!(rehearsal_sample)

    assert :ok = Postgres.record_samples([flight_sample, rehearsal_sample])

    assert Postgres.latest_value("mission-postgres-current", "HK.counter",
             realm: :flight,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-binding"
           ).raw_value == 1

    assert Postgres.latest_value("mission-postgres-current", "HK.counter",
             realm: :rehearsal,
             data_source_id: "rehearsal-questdb",
             source_binding_id: "rehearsal-binding"
           ).raw_value == 2

    assert [] =
             Postgres.latest_values_for_mission("mission-postgres-current",
               realm: :rehearsal,
               data_source_id: "flight-questdb"
             )
  end

  defp sample(sample_id, raw_value, receipt_time, opts) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-postgres-current",
      spacecraft_id: nil,
      point_id: "HK.counter",
      point_name: "HK.counter",
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

  defp persist_sample_scope!(%Sample{} = sample) do
    raw_evidence =
      RawEvidence.new(%{
        evidence_id: sample.evidence_id,
        mission_id: sample.mission_id,
        spacecraft_id: sample.spacecraft_id,
        protocol_family: :space_packet,
        direction: :downlink,
        raw: <<0, 1, 2, 3>>,
        source_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        source_ref: "test-source",
        metadata: %{}
      })

    packet_record = %PacketRecord{
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 1,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<0, 1, 2, 3>>,
      source_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: %{}
    }

    {:ok, _raw_evidence_row} = Repo.insert(RawEvidenceRow.changeset(raw_evidence))
    {:ok, _packet_record_row} = Repo.insert(PacketRecordRow.changeset(packet_record))

    :ok
  end
end
