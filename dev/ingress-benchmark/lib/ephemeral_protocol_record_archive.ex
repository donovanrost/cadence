defmodule Cadence.IngressBenchmark.EphemeralProtocolRecordArchive do
  @moduledoc false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{PacketRecord, TransferFrameRecord}
  alias Cadence.Replay.Scope
  alias Ecto.Multi

  @behaviour Cadence.Protocol.RecordArchive
  @counter_key {__MODULE__, :counters}
  @evidence_count 1
  @frame_count 2
  @packet_count 3
  @represented_bytes 4
  @batch_count 5

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_records_multi(%Multi{} = multi, %RawEvidence{}, frames, packets)
      when is_list(frames) and is_list(packets),
      do: multi

  @impl true
  def persist_records(%RawEvidence{} = evidence, frames, packets)
      when is_list(frames) and is_list(packets) do
    persist_records_many([{evidence, frames, packets}])
  end

  def persist_records_many(records_batch) when is_list(records_batch) do
    {evidence_count, frame_count, packet_count, represented_bytes} =
      Enum.reduce(records_batch, {0, 0, 0, 0}, fn
        {%RawEvidence{} = evidence, frames, packets}, {evidence_acc, frame_acc, packet_acc, bytes}
        when is_list(frames) and is_list(packets) ->
          {
            evidence_acc + 1,
            frame_acc + Enum.count(frames, &match?(%TransferFrameRecord{}, &1)),
            packet_acc + Enum.count(packets, &match?(%PacketRecord{}, &1)),
            bytes + byte_size(evidence.raw)
          }
      end)

    counters = counters()
    _ = :atomics.add(counters, @evidence_count, evidence_count)
    _ = :atomics.add(counters, @frame_count, frame_count)
    _ = :atomics.add(counters, @packet_count, packet_count)
    _ = :atomics.add(counters, @represented_bytes, represented_bytes)
    _ = :atomics.add(counters, @batch_count, 1)
    :ok
  end

  @impl true
  def fetch_packet_records(_mission_id, %Scope{}),
    do: {:error, :ephemeral_archive_not_retained}

  @impl true
  def fetch_transfer_frame_records(_mission_id, %Scope{}),
    do: {:error, :ephemeral_archive_not_retained}

  @impl true
  def flush(_mission_id), do: :ok

  @impl true
  def reset do
    :persistent_term.put(@counter_key, :atomics.new(5, signed: false))
    :ok
  end

  @impl true
  def stats(_mission_id) do
    snapshot = snapshot()

    %{
      queue_depth: 0,
      oldest_buffered_age_ms: 0,
      flush_count: snapshot.batch_count,
      flush_failure_count: 0,
      last_flush_error: nil,
      flushed_count: snapshot.evidence_count,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: snapshot.represented_bytes,
      avg_segment_bytes: 0.0
    }
  end

  @impl true
  def reset_stats(_mission_id), do: reset()

  def snapshot do
    counters = counters()

    %{
      evidence_count: :atomics.get(counters, @evidence_count),
      frame_count: :atomics.get(counters, @frame_count),
      packet_count: :atomics.get(counters, @packet_count),
      represented_bytes: :atomics.get(counters, @represented_bytes),
      batch_count: :atomics.get(counters, @batch_count),
      retention: :none
    }
  end

  defp counters do
    :persistent_term.get(@counter_key)
  rescue
    ArgumentError ->
      :ok = reset()
      :persistent_term.get(@counter_key)
  end
end
