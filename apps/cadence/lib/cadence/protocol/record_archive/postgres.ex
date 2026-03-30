defmodule Cadence.Protocol.RecordArchive.Postgres do
  @moduledoc """
  Compatibility protocol-record archive backend backed by the existing Postgres
  packet and transfer-frame tables.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Persistence.Schemas.{
    PacketRecordRow,
    RawEvidenceRow,
    TransferFrameRecordRow
  }

  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  @behaviour Cadence.Protocol.RecordArchive

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_records_multi(
        %Multi{} = multi,
        %RawEvidence{},
        transfer_frame_records,
        packet_records
      )
      when is_list(transfer_frame_records) and is_list(packet_records) do
    multi
    |> add_transfer_frame_record_inserts(transfer_frame_records)
    |> add_packet_record_inserts(packet_records)
  end

  @impl true
  def persist_records(%RawEvidence{}, _transfer_frame_records, _packet_records), do: :ok

  @impl true
  def fetch_packet_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    records =
      PacketRecordRow
      |> join(:inner, [packet], evidence in RawEvidenceRow,
        on: evidence.evidence_id == packet.evidence_id
      )
      |> where([packet, _evidence], packet.mission_id == ^mission_id)
      |> maybe_filter_packet_scope(scope)
      |> order_by([packet, _evidence], asc: packet.receipt_time, asc: packet.packet_id)
      |> maybe_limit_scope(scope.limit)
      |> Repo.all()
      |> Enum.map(fn {packet_row, _evidence_row} -> packet_record_row_to_domain(packet_row) end)

    case scope.evidence_ids do
      evidence_ids when is_list(evidence_ids) and evidence_ids != [] ->
        if records == [] do
          {:error, {:evidence_not_found, Enum.uniq(evidence_ids)}}
        else
          {:ok, records}
        end

      _other ->
        case records do
          [] -> {:error, :empty_replay_scope}
          _ -> {:ok, records}
        end
    end
  end

  @impl true
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    records =
      TransferFrameRecordRow
      |> join(:inner, [frame], evidence in RawEvidenceRow,
        on: evidence.evidence_id == frame.evidence_id
      )
      |> where([frame, _evidence], frame.mission_id == ^mission_id)
      |> maybe_filter_frame_scope(scope)
      |> order_by([frame, _evidence], asc: frame.receipt_time, asc: frame.frame_record_id)
      |> maybe_limit_scope(scope.limit)
      |> Repo.all()
      |> Enum.map(fn {frame_row, _evidence_row} ->
        transfer_frame_record_row_to_domain(frame_row)
      end)

    case scope.evidence_ids do
      evidence_ids when is_list(evidence_ids) and evidence_ids != [] ->
        if records == [] do
          {:error, {:evidence_not_found, Enum.uniq(evidence_ids)}}
        else
          {:ok, records}
        end

      _other ->
        case records do
          [] -> {:error, :empty_replay_scope}
          _ -> {:ok, records}
        end
    end
  end

  @impl true
  def flush(_mission_id), do: :ok

  @impl true
  def reset do
    _ = Repo.delete_all(PacketRecordRow)
    _ = Repo.delete_all(TransferFrameRecordRow)
    :ok
  end

  @impl true
  def stats(_mission_id) do
    %{
      queue_depth: 0,
      oldest_buffered_age_ms: 0,
      flush_count: 0,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: 0,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: 0,
      avg_segment_bytes: 0.0
    }
  end

  @impl true
  def reset_stats(_mission_id), do: :ok

  defp add_packet_record_inserts(%Multi{} = multi, packet_records) do
    Enum.reduce(packet_records, multi, fn %PacketRecord{} = packet_record, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:packet_record, packet_record.packet_id},
        PacketRecordRow.changeset(packet_record)
      )
    end)
  end

  defp add_transfer_frame_record_inserts(%Multi{} = multi, frame_records) do
    Enum.reduce(frame_records, multi, fn %TransferFrameRecord{} = frame_record, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:transfer_frame_record, frame_record.frame_record_id},
        TransferFrameRecordRow.changeset(frame_record)
      )
    end)
  end

  defp maybe_filter_packet_scope(query, %Scope{} = scope) do
    query
    |> maybe_filter_evidence_ids(scope.evidence_ids)
    |> maybe_filter_from_receipt_time(scope.from_receipt_time)
    |> maybe_filter_to_receipt_time(scope.to_receipt_time)
    |> maybe_filter_spacecraft(scope.spacecraft_id)
    |> maybe_filter_source_ref(scope.source_ref)
    |> maybe_filter_realized_contact_id(scope.realized_contact_id)
    |> maybe_filter_metadata_match(scope.metadata_match)
  end

  defp maybe_filter_frame_scope(query, %Scope{} = scope) do
    query
    |> maybe_filter_evidence_ids(scope.evidence_ids)
    |> maybe_filter_from_receipt_time(scope.from_receipt_time)
    |> maybe_filter_to_receipt_time(scope.to_receipt_time)
    |> maybe_filter_spacecraft(scope.spacecraft_id)
    |> maybe_filter_source_ref(scope.source_ref)
    |> maybe_filter_realized_contact_id(scope.realized_contact_id)
    |> maybe_filter_metadata_match(scope.metadata_match)
  end

  defp maybe_filter_evidence_ids(query, nil), do: query

  defp maybe_filter_evidence_ids(query, evidence_ids)
       when is_list(evidence_ids) and evidence_ids != [] do
    where(query, [record, _evidence], record.evidence_id in ^Enum.uniq(evidence_ids))
  end

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = from_receipt_time) do
    where(query, [record, _evidence], record.receipt_time >= ^from_receipt_time)
  end

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = to_receipt_time) do
    where(query, [record, _evidence], record.receipt_time <= ^to_receipt_time)
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) when is_binary(spacecraft_id) do
    where(query, [record, _evidence], record.spacecraft_id == ^spacecraft_id)
  end

  defp maybe_filter_source_ref(query, nil), do: query

  defp maybe_filter_source_ref(query, source_ref) when is_binary(source_ref) do
    where(query, [_record, evidence], evidence.source_ref == ^source_ref)
  end

  defp maybe_filter_realized_contact_id(query, nil), do: query

  defp maybe_filter_realized_contact_id(query, realized_contact_id)
       when is_binary(realized_contact_id) do
    where(
      query,
      [_record, evidence],
      fragment("? ->> 'realized_contact_id' = ?", evidence.metadata, ^realized_contact_id)
    )
  end

  defp maybe_filter_metadata_match(query, nil), do: query

  defp maybe_filter_metadata_match(query, metadata_match)
       when is_map(metadata_match) and map_size(metadata_match) > 0 do
    Enum.reduce(metadata_match, query, fn {key, value}, acc ->
      where(
        acc,
        [_record, evidence],
        fragment("? ->> ? = ?", evidence.metadata, ^to_string(key), ^to_string(value))
      )
    end)
  end

  defp maybe_filter_metadata_match(query, _metadata_match), do: query

  defp maybe_limit_scope(query, nil), do: query
  defp maybe_limit_scope(query, limit), do: limit(query, ^limit)

  defp packet_record_row_to_domain(%PacketRecordRow{} = row) do
    %PacketRecord{
      packet_id: row.packet_id,
      evidence_id: row.evidence_id,
      mission_id: row.mission_id,
      source_endpoint_ref: row.source_endpoint_ref,
      spacecraft_id: row.spacecraft_id,
      protocol_family: String.to_existing_atom(row.protocol_family),
      packet_kind: String.to_existing_atom(row.packet_kind),
      apid: row.apid,
      sequence_flags: row.sequence_flags,
      sequence_count: row.sequence_count,
      secondary_header?: row.secondary_header,
      packet_data: row.packet_data,
      source_time: row.source_time,
      receipt_time: row.receipt_time,
      provenance: row.provenance || %{}
    }
  end

  defp transfer_frame_record_row_to_domain(%TransferFrameRecordRow{} = row) do
    %TransferFrameRecord{
      frame_record_id: row.frame_record_id,
      evidence_id: row.evidence_id,
      mission_id: row.mission_id,
      source_endpoint_ref: row.source_endpoint_ref,
      spacecraft_id: row.spacecraft_id,
      protocol_family: String.to_existing_atom(row.protocol_family),
      direction: String.to_existing_atom(row.direction),
      scid: row.scid,
      vcid: row.vcid,
      map_id: row.map_id,
      frame_seq: row.frame_seq,
      raw_frame_offset_bytes: row.raw_frame_offset_bytes,
      raw_frame_length_bytes: row.raw_frame_length_bytes,
      payload_length_bytes: row.payload_length_bytes,
      first_header_pointer: row.first_header_pointer,
      quality: decode_quality(row.quality),
      source_time: row.source_time,
      receipt_time: row.receipt_time,
      metadata: row.metadata || %{}
    }
  end

  defp decode_quality(nil), do: nil
  defp decode_quality(value) when is_binary(value), do: String.to_existing_atom(value)
end
