defmodule Cadence.Runtime.SemanticSnapshotNotifier do
  @moduledoc """
  Tells a journal's processing consumer how far a partition's semantic snapshot reaches
  (DECISIONS #94/#96). The consumer's durable cursor may only follow snapshots, so the partition
  sends `{:semantic_snapshot_durable, partition_id, stream_id, offset}` to every consumer of each
  stream its snapshot covers, once the snapshot is committed.

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

  defp running?, do: Process.whereis(@scope) != nil
end
