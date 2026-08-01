defmodule Cadence.IngressBenchmark.EphemeralIngressArchive do
  @moduledoc false

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.{Batch, Receipt}
  alias Cadence.Replay.Scope
  alias Ecto.Multi

  @behaviour Cadence.IngressArchive
  @counter_key {__MODULE__, :counters}
  @persisted_count 1
  @persisted_bytes 2
  @batch_count 3

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_raw_evidence_multi(%Multi{} = multi, %RawEvidence{}), do: multi

  @impl true
  def persist_raw_evidence(%RawEvidence{} = raw_evidence) do
    persist_raw_evidences([raw_evidence])
  end

  @impl true
  def persist_batch(%Batch{} = batch) do
    :ok = record_batch(batch.raw_evidences)
    {:ok, Receipt.for_batch(batch, :accepted)}
  end

  def persist_raw_evidences(raw_evidences) when is_list(raw_evidences) do
    record_batch(raw_evidences)
  end

  defp record_batch(raw_evidences) do
    byte_count = Enum.reduce(raw_evidences, 0, &(&2 + byte_size(&1.raw)))
    counters = counters()
    _ = :atomics.add(counters, @persisted_count, length(raw_evidences))
    _ = :atomics.add(counters, @persisted_bytes, byte_count)
    _ = :atomics.add(counters, @batch_count, 1)
    :ok
  end

  @impl true
  def fetch_raw_evidences(_mission_id, %Scope{}), do: {:error, :ephemeral_archive_not_retained}

  @impl true
  def flush(_mission_id), do: :ok

  @impl true
  def reset do
    :persistent_term.put(@counter_key, :atomics.new(3, signed: false))
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
      flushed_count: snapshot.persisted_count,
      segment_count: 0,
      flush_total_us: 0,
      avg_flush_us: 0.0,
      flushed_bytes_total: snapshot.persisted_bytes,
      avg_segment_bytes: 0.0
    }
  end

  @impl true
  def reset_stats(_mission_id), do: reset()

  def snapshot do
    counters = counters()

    %{
      persisted_count: :atomics.get(counters, @persisted_count),
      persisted_bytes: :atomics.get(counters, @persisted_bytes),
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
