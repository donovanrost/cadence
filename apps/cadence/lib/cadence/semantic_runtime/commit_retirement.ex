defmodule Cadence.SemanticRuntime.CommitRetirement do
  @moduledoc """
  Retires semantic runtime commits that sit behind their partition's checkpoint (DECISIONS #94,
  #101's rules). Recovery starts at the checkpoint and replays only what follows it, so older
  `updates` commits are never read again except by `Store.recover/3`'s full-history audit, which
  after this audits from the checkpoint on.

  `Store` publishes a checkpoint with every commit, so a partition's checkpoint is its latest
  commit. Retired: `input_kind = 'updates'` commits strictly below their partition's checkpoint.
  Always kept:

    * every commit ANY checkpoint references (`semantic_runtime_checkpoints.commit_sequence` is
      `ON DELETE CASCADE`: deleting one would delete its checkpoint);
    * everything at or after the checkpoint;
    * `timer`, `seed` and NULL-kind (legacy) commits, which timer cursors and pending timers read.

  Only QUIET partitions are touched: no commit for `quiet_ms` (a pass has ended, or the partition
  is idle). Each batch is ONE statement in its own transaction that re-reads the checkpoints and
  re-checks the quiet period, so a pass that starts mid-run stops the run at the next batch.
  Batches are keyset-paged and bounded. Nothing here vacuums: Postgres reuses the space.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.SemanticRuntime.{Checkpoint, CommitRow}

  @table "semantic_runtime_commits"
  @checkpoints "semantic_runtime_checkpoints"

  @type partition :: %{
          organization_scope_id: binary(),
          mission_id: binary(),
          partition_id: binary(),
          runtime_basis_sha256: binary()
        }

  @type outcome :: %{
          rows: non_neg_integer(),
          batches: non_neg_integer(),
          ms: non_neg_integer(),
          stopped: :done | :batch_limit | :checkpoint_count_dropped
        }

  @doc """
  Partitions with a checkpoint whose latest commit is older than `cutoff`. A partition still in a
  pass (a commit since `cutoff`) is never listed.
  """
  @spec quiet_partitions(DateTime.t()) :: [partition()]
  def quiet_partitions(%DateTime{} = cutoff) do
    latest_at =
      from(c in CommitRow,
        where:
          c.organization_scope_id == parent_as(:checkpoint).organization_scope_id and
            c.mission_id == parent_as(:checkpoint).mission_id and
            c.partition_id == parent_as(:checkpoint).partition_id and
            c.runtime_basis_sha256 == parent_as(:checkpoint).runtime_basis_sha256,
        order_by: [desc: c.commit_sequence],
        limit: 1,
        select: c.inserted_at
      )

    from(k in Checkpoint,
      as: :checkpoint,
      inner_lateral_join: latest in subquery(latest_at),
      on: true,
      where: latest.inserted_at < ^cutoff,
      order_by: [k.mission_id, k.partition_id, k.runtime_basis_sha256],
      select: %{
        organization_scope_id: k.organization_scope_id,
        mission_id: k.mission_id,
        partition_id: k.partition_id,
        runtime_basis_sha256: k.runtime_basis_sha256
      }
    )
    |> Repo.all()
  end

  @doc """
  The commits a run would retire in `partition` now (`:dry`): the same predicate, counted.
  """
  @spec retirable_count(partition(), DateTime.t()) :: non_neg_integer()
  def retirable_count(partition, %DateTime{} = cutoff) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM #{@table} c WHERE #{predicate()}",
        params(partition, cutoff, 0)
      )

    count
  end

  @doc """
  Retires `partition`'s retirable commits in batches of `batch_size`, at most `max_batches`,
  pausing `pause_ms` between them. Stops early when a batch deletes nothing (done, or the
  partition's pass started: the quiet check fails inside the statement) or when the checkpoint
  count drops below its count at the start (it never should; deletes here can't reach a
  referenced commit).
  """
  @spec retire(partition(), DateTime.t(), keyword()) :: outcome()
  def retire(partition, %DateTime{} = cutoff, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 5_000)
    max_batches = Keyword.get(opts, :max_batches, 40)
    pause_ms = Keyword.get(opts, :pause_ms, 200)
    count_checkpoints = Keyword.get(opts, :checkpoint_count, &checkpoint_count/0)
    started = System.monotonic_time(:millisecond)
    checkpoints = count_checkpoints.()

    run = %{
      partition: partition,
      cutoff: cutoff,
      batch_size: batch_size,
      max_batches: max_batches,
      pause_ms: pause_ms,
      count_checkpoints: count_checkpoints,
      checkpoints: checkpoints
    }

    {rows, batches, stopped} = batches(run, 1, 0, 0)

    %{
      rows: rows,
      batches: batches,
      ms: System.monotonic_time(:millisecond) - started,
      stopped: stopped
    }
  end

  # Batch `batch` after `after_seq`, with `rows` retired so far: {rows, batches, why it stopped}.
  defp batches(run, batch, rows, after_seq) do
    case retire_batch(run.partition, run.cutoff, after_seq, run.batch_size) do
      {0, _last} ->
        {rows, batch - 1, :done}

      {deleted, last} ->
        next_batch(run, batch, rows + deleted, last)
    end
  end

  defp next_batch(run, batch, rows, last) do
    cond do
      run.count_checkpoints.() < run.checkpoints -> {rows, batch, :checkpoint_count_dropped}
      batch >= run.max_batches -> {rows, batch, :batch_limit}
      true -> pause_then_continue(run, batch, rows, last)
    end
  end

  defp pause_then_continue(run, batch, rows, last) do
    if run.pause_ms > 0, do: Process.sleep(run.pause_ms)
    batches(run, batch + 1, rows, last)
  end

  @doc """
  The foreign keys that reference the commits table, other than the checkpoints' own. A run
  refuses to start unless this is empty: another referencing table would need its own rule.
  """
  @spec unexpected_foreign_keys() :: [binary()]
  def unexpected_foreign_keys do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT conrelid::regclass::text || ' ' || conname
        FROM pg_constraint
        WHERE confrelid = '#{@table}'::regclass AND contype = 'f'
          AND conrelid <> '#{@checkpoints}'::regclass
        ORDER BY 1
        """,
        []
      )

    Enum.map(rows, fn [name] -> name end)
  end

  @spec checkpoint_count() :: non_neg_integer()
  def checkpoint_count, do: Repo.aggregate(Checkpoint, :count)

  # One statement, one transaction: the candidates re-read the checkpoints and the quiet period.
  defp retire_batch(partition, cutoff, after_seq, batch_size) do
    %{rows: [[deleted, last]]} =
      Repo.query!(
        """
        WITH doomed AS (
          SELECT c.commit_sequence FROM #{@table} c
          WHERE #{predicate()}
          ORDER BY c.commit_sequence
          LIMIT $7
        ), gone AS (
          DELETE FROM #{@table} p USING doomed d
          WHERE p.commit_sequence = d.commit_sequence
          RETURNING p.commit_sequence
        )
        SELECT count(*), coalesce(max(commit_sequence), $6) FROM gone
        """,
        params(partition, cutoff, after_seq) ++ [batch_size]
      )

    {deleted, last}
  end

  # $1-$4 the partition, $5 the quiet cutoff, $6 the keyset (last retired sequence).
  defp predicate do
    """
    c.organization_scope_id = $1 AND c.mission_id = $2 AND c.partition_id = $3
      AND c.runtime_basis_sha256 = $4
      AND c.input_kind = 'updates'
      AND c.commit_sequence > $6
      AND c.commit_sequence < (
        SELECT k.commit_sequence FROM #{@checkpoints} k
        WHERE k.organization_scope_id = $1 AND k.mission_id = $2 AND k.partition_id = $3
          AND k.runtime_basis_sha256 = $4)
      AND NOT EXISTS (
        SELECT 1 FROM #{@checkpoints} kc WHERE kc.commit_sequence = c.commit_sequence)
      AND (
        SELECT r.inserted_at FROM #{@table} r
        WHERE r.organization_scope_id = $1 AND r.mission_id = $2 AND r.partition_id = $3
          AND r.runtime_basis_sha256 = $4
        ORDER BY r.commit_sequence DESC LIMIT 1) < $5
    """
  end

  defp params(partition, cutoff, after_seq) do
    [
      partition.organization_scope_id,
      partition.mission_id,
      partition.partition_id,
      partition.runtime_basis_sha256,
      # inserted_at is a timestamp without time zone (UTC).
      DateTime.to_naive(cutoff),
      after_seq
    ]
  end
end
