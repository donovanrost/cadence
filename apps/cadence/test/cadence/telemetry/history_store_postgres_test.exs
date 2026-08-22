defmodule Cadence.Telemetry.HistoryStorePostgresTest do
  use Cadence.DataCase, async: false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Telemetry.HistoryStore.Postgres
  alias Cadence.Telemetry.Sample

  setup do
    persist_mission_scope("org-postgres-history", "mission-postgres-history")
    :ok
  end

  test "filters and orders generation-time history by observed source time" do
    late_receipt =
      sample("sample-late-receipt", 30, ~U[2026-06-21 12:30:00Z],
        generation_time: ~U[2026-06-21 12:00:00Z]
      )

    early_receipt =
      sample("sample-early-receipt", 20, ~U[2026-06-21 12:01:00Z],
        generation_time: ~U[2026-06-21 12:05:00Z]
      )

    outside_window =
      sample("sample-outside-window", 10, ~U[2026-06-21 12:02:00Z],
        generation_time: ~U[2026-06-21 11:55:00Z]
      )

    persist_sample_scope!(late_receipt)
    persist_sample_scope!(early_receipt)
    persist_sample_scope!(outside_window)

    assert :ok = Postgres.persist_samples([early_receipt, outside_window, late_receipt])

    assert ["sample-late-receipt", "sample-early-receipt"] =
             Postgres.sample_history("mission-postgres-history", "HK.counter",
               time_axis: :generation_time,
               from_observed_at: ~U[2026-06-21 11:59:00Z],
               to_observed_at: ~U[2026-06-21 12:06:00Z],
               order: :asc,
               limit: 10
             )
             |> Enum.map(& &1.sample_id)
  end

  defp sample(sample_id, raw_value, receipt_time, opts) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-postgres-history",
      spacecraft_id: "sc-postgres-history",
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
      generation_time: Keyword.fetch!(opts, :generation_time),
      provenance: %{}
    }
  end

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
