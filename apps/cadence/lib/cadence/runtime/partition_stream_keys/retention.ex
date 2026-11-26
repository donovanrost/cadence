defmodule Cadence.Runtime.PartitionStreamKeys.Retention do
  @moduledoc """
  Retention for `partition_stream_keys` (#694). The dangerous one.

  An ordinal is allocated once and kept so that a replay of a journal stream gets the same
  replay-safe effect ids (DECISIONS #99). If a stream's key were deleted and the stream replayed,
  the replay would allocate a *new* ordinal and its effects would get new ids: duplicates. So a
  key goes only when its stream can no longer be replayed, which is the replay horizon
  (`Cadence.Persistence.Retention.replay_horizon_days/1`: the longest of the archives' and the
  journal's retention, plus a margin) after it was allocated.

  The reserved keys, the ones for a partition's timers and its application initialisation
  (`timer_stream/0`, `init_stream/0`, which may embed a capability instance id), never go: a live
  partition keeps using them, and renumbering them would renumber its effects. There are one or
  two per partition, so keeping them is bounded.

  A chunk deletes the oldest `chunk_rows` expired keys by ordinal (an ordinal grows with its
  insertion time, so the scan starts at the old end), skipping rows another transaction holds.
  """

  @behaviour Cadence.Persistence.Retention.Rule

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @impl true
  def name, do: :partition_stream_keys

  @impl true
  def enabled?(_settings), do: true

  @impl true
  def initial_cursor, do: nil

  @impl true
  def sweep_chunk(_cursor, %DateTime{} = now, settings) do
    cutoff = now |> Retention.cutoff(Retention.replay_horizon_days(settings)) |> naive()
    limit = Keyword.fetch!(settings, :chunk_rows)

    %{num_rows: deleted} =
      Repo.query!(
        """
        WITH doomed AS (
          SELECT ordinal FROM partition_stream_keys
          WHERE inserted_at < $1
            AND NOT (starts_with(stream_key, 'timer') OR starts_with(stream_key, 'init'))
          ORDER BY ordinal
          LIMIT $2
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM partition_stream_keys k USING doomed d WHERE k.ordinal = d.ordinal
        """,
        [cutoff, limit]
      )

    {if(deleted < limit, do: :done, else: :more), deleted, nil, fn -> :ok end}
  end

  # `inserted_at` is a UTC column without a time zone.
  defp naive(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()
end
