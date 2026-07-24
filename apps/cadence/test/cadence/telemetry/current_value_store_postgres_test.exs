defmodule Cadence.Telemetry.CurrentValueStorePostgresTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Telemetry.CurrentValueStore.Postgres
  alias Cadence.Telemetry.Sample

  setup do
    scope_id = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-postgres-current-" <> scope_id

    persist_mission_scope("org-postgres-current-" <> scope_id, mission_id)

    {:ok, mission_id: mission_id, scope_id: scope_id}
  end

  test "does not replace current state with a late-arriving older source-time sample", %{
    mission_id: mission_id,
    scope_id: scope_id
  } do
    current_sample =
      sample("sample-current", 20, ~U[2026-06-21 12:10:05Z],
        mission_id: mission_id,
        scope_id: scope_id,
        generation_time: ~U[2026-06-21 12:10:00Z]
      )

    late_arrival =
      sample("sample-late", 10, ~U[2026-06-21 12:15:00Z],
        mission_id: mission_id,
        scope_id: scope_id,
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    persist_sample_scope!(current_sample)
    persist_sample_scope!(late_arrival)

    assert :ok = Postgres.record_samples([current_sample])
    assert :ok = Postgres.record_samples([late_arrival])

    latest_sample = Postgres.latest_value(mission_id, "HK.counter", [])
    assert latest_sample.sample_id == scoped_id("sample-current", scope_id)
    assert latest_sample.raw_value == 20
  end

  test "uses receipt time when generation time is missing", %{
    mission_id: mission_id,
    scope_id: scope_id
  } do
    older_sample =
      sample("sample-old", 10, ~U[2026-06-21 12:00:00Z],
        mission_id: mission_id,
        scope_id: scope_id,
        generation_time: nil
      )

    newer_sample =
      sample("sample-new", 20, ~U[2026-06-21 12:00:01Z],
        mission_id: mission_id,
        scope_id: scope_id,
        generation_time: nil
      )

    persist_sample_scope!(older_sample)
    persist_sample_scope!(newer_sample)

    assert :ok = Postgres.record_samples([older_sample, newer_sample])

    latest_sample = Postgres.latest_value(mission_id, "HK.counter", [])
    assert latest_sample.sample_id == scoped_id("sample-new", scope_id)
    assert latest_sample.raw_value == 20
  end

  test "does not replace canonical current state with unresolved conflicts", %{
    mission_id: mission_id,
    scope_id: scope_id
  } do
    canonical =
      sample("sample-canonical", 20, ~U[2026-06-21 12:10:00Z],
        mission_id: mission_id,
        scope_id: scope_id,
        validity_state: :canonical
      )

    conflict =
      sample("sample-conflict", 99, ~U[2026-06-21 12:11:00Z],
        mission_id: mission_id,
        scope_id: scope_id,
        validity_state: :conflict
      )

    persist_sample_scope!(canonical)
    persist_sample_scope!(conflict)

    assert :ok = Postgres.record_samples([canonical])
    assert :ok = Postgres.record_samples([conflict])

    latest_sample = Postgres.latest_value(mission_id, "HK.counter", [])
    assert latest_sample.sample_id == scoped_id("sample-canonical", scope_id)
    assert latest_sample.raw_value == 20

    assert [] =
             Postgres.latest_values_for_mission(mission_id,
               validity_state: :conflict
             )
  end

  test "separates current values by storage source context", %{
    mission_id: mission_id,
    scope_id: scope_id
  } do
    flight_sample =
      sample("sample-flight", 1, ~U[2026-06-21 12:00:00Z],
        mission_id: mission_id,
        scope_id: scope_id,
        realm: :flight,
        data_source_id: "flight-questdb",
        binding_id: "flight-binding"
      )

    rehearsal_sample =
      sample("sample-rehearsal", 2, ~U[2026-06-21 12:01:00Z],
        mission_id: mission_id,
        scope_id: scope_id,
        realm: :rehearsal,
        data_source_id: "rehearsal-questdb",
        binding_id: "rehearsal-binding"
      )

    persist_sample_scope!(flight_sample)
    persist_sample_scope!(rehearsal_sample)

    assert :ok = Postgres.record_samples([flight_sample, rehearsal_sample])

    assert Postgres.latest_value(mission_id, "HK.counter",
             realm: :flight,
             data_source_id: "flight-questdb",
             source_binding_id: "flight-binding"
           ).raw_value == 1

    assert Postgres.latest_value(mission_id, "HK.counter",
             realm: :rehearsal,
             data_source_id: "rehearsal-questdb",
             source_binding_id: "rehearsal-binding"
           ).raw_value == 2

    assert [] =
             Postgres.latest_values_for_mission(mission_id,
               realm: :rehearsal,
               data_source_id: "flight-questdb"
             )
  end

  defp sample(sample_id, raw_value, receipt_time, opts) do
    scope_id = Keyword.fetch!(opts, :scope_id)
    scoped_sample_id = scoped_id(sample_id, scope_id)

    %Sample{
      sample_id: scoped_sample_id,
      mission_id: Keyword.fetch!(opts, :mission_id),
      spacecraft_id: nil,
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> scoped_sample_id,
      evidence_id: "evidence-" <> scoped_sample_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      receipt_time: receipt_time,
      generation_time: Keyword.get(opts, :generation_time, receipt_time),
      provenance: provenance(opts)
    }
  end

  defp scoped_id(value, scope_id), do: value <> "-" <> scope_id

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
