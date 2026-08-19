defmodule Cadence.Protocol.RecordArchive.Postgres do
  @moduledoc """
  Compatibility protocol-record archive backend backed by the existing Postgres
  packet and transfer-frame tables.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive

  alias Cadence.Protocol.RecordArchive.Postgres.{
    PacketRecordRow,
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
  def persist_records_multi(
        %Multi{} = multi,
        %RawEvidence{} = raw_evidence,
        transfer_frame_records,
        packet_records,
        backend_opts
      )
      when is_list(transfer_frame_records) and is_list(packet_records) and
             is_list(backend_opts) do
    persist_records_multi(multi, raw_evidence, transfer_frame_records, packet_records)
  end

  @impl true
  def persist_records(%RawEvidence{}, _transfer_frame_records, _packet_records), do: :ok

  @impl true
  def persist_records(
        %RawEvidence{} = raw_evidence,
        transfer_frame_records,
        packet_records,
        backend_opts
      )
      when is_list(transfer_frame_records) and is_list(packet_records) and
             is_list(backend_opts) do
    persist_records(raw_evidence, transfer_frame_records, packet_records)
  end

  @impl true
  def persist_records_many(records_batch) when is_list(records_batch) do
    case Enum.all?(records_batch, fn
           {%RawEvidence{}, transfer_frame_records, packet_records}
           when is_list(transfer_frame_records) and is_list(packet_records) ->
             true

           _other ->
             false
         end) do
      true -> :ok
      false -> {:error, :invalid_protocol_record_batch}
    end
  end

  @impl true
  def persist_records_many(records_batch, backend_opts)
      when is_list(records_batch) and is_list(backend_opts) do
    persist_records_many(records_batch)
  end

  @impl true
  def fetch_packet_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_packet_records(mission_id, scope, [])
  end

  @impl true
  def fetch_packet_records(mission_id, %Scope{} = scope, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    repo = repo(backend_opts)

    with {:ok, evidence_ids} <- evidence_ids_for_scope(mission_id, scope) do
      records =
        PacketRecordRow
        |> where(
          [packet],
          packet.mission_id == ^mission_id and packet.evidence_id in ^evidence_ids
        )
        |> order_by([packet], asc: packet.receipt_time, asc: packet.packet_id)
        |> maybe_limit_scope(scope.limit)
        |> repo.all()
        |> Enum.map(&packet_record_row_to_domain/1)

      replay_scope_result(records, scope)
    end
  end

  @impl true
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope) when is_binary(mission_id) do
    fetch_transfer_frame_records(mission_id, scope, [])
  end

  @impl true
  def fetch_transfer_frame_records(mission_id, %Scope{} = scope, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts) do
    repo = repo(backend_opts)

    with {:ok, evidence_ids} <- evidence_ids_for_scope(mission_id, scope) do
      records =
        TransferFrameRecordRow
        |> where(
          [frame],
          frame.mission_id == ^mission_id and frame.evidence_id in ^evidence_ids
        )
        |> order_by([frame], asc: frame.receipt_time, asc: frame.frame_record_id)
        |> maybe_limit_scope(scope.limit)
        |> repo.all()
        |> Enum.map(&transfer_frame_record_row_to_domain/1)

      replay_scope_result(records, scope)
    end
  end

  @impl true
  def flush(_mission_id), do: :ok

  @impl true
  def flush(_mission_id, backend_opts) when is_list(backend_opts), do: :ok

  @impl true
  def reset do
    reset([])
  end

  @impl true
  def reset(backend_opts) when is_list(backend_opts) do
    repo = repo(backend_opts)
    _ = repo.delete_all(PacketRecordRow)
    _ = repo.delete_all(TransferFrameRecordRow)
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
  def stats(mission_id, backend_opts)
      when is_binary(mission_id) and is_list(backend_opts),
      do: stats(mission_id)

  @impl true
  def reset_stats(_mission_id), do: :ok

  @impl true
  def reset_stats(_mission_id, backend_opts) when is_list(backend_opts), do: :ok

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

  defp evidence_ids_for_scope(mission_id, %Scope{} = scope) do
    case IngressArchive.fetch_raw_evidences(mission_id, %Scope{scope | limit: nil}) do
      {:ok, evidences} -> {:ok, Enum.map(evidences, & &1.evidence_id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_scope_result([], %Scope{evidence_ids: evidence_ids})
       when is_list(evidence_ids) and evidence_ids != [],
       do: {:error, {:evidence_not_found, Enum.uniq(evidence_ids)}}

  defp replay_scope_result([], _scope), do: {:error, :empty_replay_scope}
  defp replay_scope_result(records, _scope), do: {:ok, records}

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

  defp repo(backend_opts), do: Keyword.get(backend_opts, :repo, Repo)
end
