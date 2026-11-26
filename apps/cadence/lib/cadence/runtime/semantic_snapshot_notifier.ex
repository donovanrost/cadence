defmodule Cadence.Runtime.SemanticSnapshotNotifier do
  @moduledoc """
  Tells a journal's processing consumer how far a partition's semantic snapshot reaches
  (DECISIONS #94/#96). The consumer's durable cursor may only follow snapshots, so the partition
  sends `{:semantic_snapshot_durable, partition_id, stream_id, offset}` to every consumer of each
  stream its snapshot covers, once the snapshot is committed. A partition that recovers from a
  snapshot sends `{:semantic_partition_recovered, partition_id, resume}` to the consumers it has
  gated, which replay from it. A partition that stops for good
  after its final snapshot sends `{:semantic_snapshot_stopped, partition_id, stream_id}`, so it
  stops gating.

  A `:pg` scope carries it, so it reaches a consumer on another node. Consumers subscribe per
  stream; both sides tolerate the scope not running (a host without the runtime, tests).
  """

  @scope :cadence_semantic_snapshots

  @doc false
  def child_spec(_opts), do: %{id: __MODULE__, start: {:pg, :start_link, [@scope]}}

  @doc "Subscribes the calling consumer to the snapshots covering `stream_id`."
  @spec subscribe(binary()) :: :ok
  def subscribe(stream_id) when is_binary(stream_id) do
    if running?() and self() not in :pg.get_local_members(@scope, stream_id) do
      :pg.join(@scope, stream_id, self())
    end

    :ok
  end

  @doc "Subscribes the calling consumer to the recoveries of `partition_id`."
  @spec subscribe_partition(binary()) :: :ok
  def subscribe_partition(partition_id) when is_binary(partition_id) do
    group = {:partition, partition_id}

    if running?() and self() not in :pg.get_local_members(@scope, group) do
      :pg.join(@scope, group, self())
    end

    :ok
  end

  @doc """
  `partition_id` recovered from a snapshot holding `resume` (stream id => offset): a consumer that
  has processed a stream past that offset must replay it from there, because the recovered state
  does not include what came after.
  """
  @spec recovered(binary(), %{binary() => non_neg_integer()}) :: :ok
  def recovered(partition_id, resume) when is_map(resume) do
    if running?() do
      for consumer <- :pg.get_members(@scope, {:partition, partition_id}) do
        send(consumer, {:semantic_partition_recovered, partition_id, resume})
      end
    end

    :ok
  end

  @doc "Notifies the consumers of every stream in `resume` (stream id => offset)."
  @spec published(binary(), %{binary() => non_neg_integer()}) :: :ok
  def published(partition_id, resume) when is_map(resume) do
    if running?() do
      for {stream_id, offset} <- resume,
          consumer <- :pg.get_members(@scope, stream_id) do
        send(consumer, {:semantic_snapshot_durable, partition_id, stream_id, offset})
      end
    end

    :ok
  end

  @doc """
  Tells the consumers of every stream in `resume` that `partition_id` has stopped after its final
  snapshot: it no longer gates their durable cursor. A partition that comes back gates again with
  its first batch.
  """
  @spec stopped(binary(), %{binary() => non_neg_integer()}) :: :ok
  def stopped(partition_id, resume) when is_map(resume) do
    if running?() do
      for {stream_id, _offset} <- resume,
          consumer <- :pg.get_members(@scope, stream_id) do
        send(consumer, {:semantic_snapshot_stopped, partition_id, stream_id})
      end
    end

    :ok
  end

  defp running?, do: Process.whereis(@scope) != nil
end
