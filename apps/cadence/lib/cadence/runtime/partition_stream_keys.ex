defmodule Cadence.Runtime.PartitionStreamKeys do
  @moduledoc """
  The stream ordinal of replay-safe effect ids (DECISIONS #99, `Cadence.Platform.ReplayId`): one
  per (mission, runtime partition, journal stream), allocated on first use and kept for good, so
  a replay of the same stream gets the same ordinal and two streams never share one.

  Besides journal streams, a partition has two reserved keys: `"timer"` (timer-driven effects)
  and `"init"` (effects of a managed application's initialization).

  `ordinal/3` is one statement: an insert that returns the existing row on conflict. A partition
  calls it once per new stream and keeps the result, so it runs about once per contact.
  """

  import Ecto.Query

  alias Cadence.Repo

  @timer "timer"
  @init "init"

  @spec timer_stream() :: binary()
  def timer_stream, do: @timer

  @spec init_stream() :: binary()
  def init_stream, do: @init

  @doc "The ordinal of `stream_key` in this partition, allocating it the first time."
  @spec ordinal(binary(), binary(), binary()) :: {:ok, pos_integer()} | {:error, term()}
  def ordinal(mission_id, partition_id, stream_key)
      when is_binary(mission_id) and is_binary(partition_id) and is_binary(stream_key) do
    # DO UPDATE (a no-op on the key) so the existing row comes back in the same statement.
    query = """
    INSERT INTO partition_stream_keys (mission_id, partition_id, stream_key)
    VALUES ($1, $2, $3)
    ON CONFLICT (mission_id, partition_id, stream_key)
    DO UPDATE SET stream_key = EXCLUDED.stream_key
    RETURNING ordinal
    """

    case Repo.query(query, [mission_id, partition_id, stream_key]) do
      {:ok, %{rows: [[ordinal]]}} -> {:ok, ordinal}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The (partition, stream) an ordinal was allocated to, for the replay conflict check."
  @spec fetch(pos_integer()) ::
          {:ok, %{mission_id: binary(), partition_id: binary(), stream_key: binary()}}
          | {:error, :not_found}
  def fetch(ordinal) when is_integer(ordinal) do
    "partition_stream_keys"
    |> where([k], k.ordinal == ^ordinal)
    |> select([k], %{
      mission_id: k.mission_id,
      partition_id: k.partition_id,
      stream_key: k.stream_key
    })
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      key -> {:ok, key}
    end
  end
end
