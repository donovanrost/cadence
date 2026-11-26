defmodule Cadence.Runtime.IngressJournalConsumer.SnapshotGate do
  @moduledoc """
  Holds a journal's durable processing cursor at the semantic snapshots of the partitions that
  consume it (DECISIONS #94/#96, #692).

  A partition's state, and so its snapshot, lags the batches it has processed by up to 60 s. If
  the durable cursor released a batch before a snapshot covered it, a crash would lose that
  batch's semantic state: the journal would not replay it. So the durable resume point is
  `min(what processing finished, the lowest snapshot offset of any gating partition)`; the
  in-memory read cursor and backpressure are untouched.

  A partition gates the stream from its first batch (`note/2`). Until its first snapshot is
  announced (`snapshotted/3`) the durable resume point holds where it was. A batch from a
  partition that reports no gate (no semantic plan, runtime records not persisted) adds none.
  """

  defstruct partitions: MapSet.new(), offsets: %{}

  @type t :: %__MODULE__{
          partitions: MapSet.t(binary()),
          offsets: %{binary() => non_neg_integer()}
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Records that `partition` (nil: an ungated one) processed a batch of this stream."
  @spec note(t(), binary() | nil) :: t()
  def note(gate, nil), do: gate
  def note(gate, partition), do: %{gate | partitions: MapSet.put(gate.partitions, partition)}

  @doc "Records a committed snapshot: `partition`'s state includes this stream up to `offset`."
  @spec snapshotted(t(), binary(), non_neg_integer()) :: t()
  def snapshotted(gate, partition, offset),
    do: %{gate | offsets: Map.update(gate.offsets, partition, offset, &max(&1, offset))}

  @doc "`partition` stopped after its final snapshot: it gates no longer."
  @spec release(t(), binary()) :: t()
  def release(gate, partition),
    do: %{
      gate
      | partitions: MapSet.delete(gate.partitions, partition),
        offsets: Map.delete(gate.offsets, partition)
    }

  @doc """
  The durable resume point for a batch whose processing finished at `finished`, given the
  journal's current durable resume point `floor` (never lowered).
  """
  @spec limit(t(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def limit(%__MODULE__{partitions: partitions} = gate, finished, floor) do
    if MapSet.size(partitions) == 0 do
      finished
    else
      snapshot = partitions |> Enum.map(&Map.get(gate.offsets, &1, floor)) |> Enum.min()
      finished |> min(snapshot) |> max(floor)
    end
  end

  @doc "Whether the durable resume point is held back from `finished` by a snapshot."
  @spec holding?(t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def holding?(gate, finished, floor), do: limit(gate, finished, floor) < finished
end
