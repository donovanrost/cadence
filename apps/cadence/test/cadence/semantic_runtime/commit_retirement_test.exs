defmodule Cadence.SemanticRuntime.CommitRetirementTest do
  @moduledoc """
  #94's retirement job with #101's rules, on real commits and checkpoints: what is retired and
  what is always kept, quiet partitions only (an open pass is never touched), bounded batches,
  :dry, the checkpoint-count stop, the foreign-key refusal, and that recovery still restores
  from the checkpoint afterwards.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Control.{ProcessNamespace, SemanticCommitRetirement}
  alias Cadence.Repo
  alias Cadence.SemanticRuntime.{Checkpoint, CommitRetirement, CommitRow, State, Terms}
  alias Ecto.Adapters.SQL.Sandbox

  @now ~U[2026-11-17 12:00:00.000000Z]

  setup do
    %{a: partition("a"), b: partition("b")}
  end

  describe "what a run retires" do
    test "updates behind the checkpoint go; the checkpoint's commit, later, timer, seed and legacy commits stay",
         %{a: a} do
      u1 = commit(a, "updates", -600)
      u2 = commit(a, "updates", -590)
      timer = commit(a, "timer", -580)
      legacy = commit(a, nil, -570)
      seed = commit(a, "seed", -560)
      checkpointed = commit(a, "updates", -550, checkpoint: true)
      later = commit(a, "updates", -540)

      assert [%{rows: 2, stopped: :done}] = live_run()

      assert gone?(u1) and gone?(u2)
      refute Enum.any?([timer, legacy, seed, checkpointed, later], &gone?/1)
      assert Repo.aggregate(Checkpoint, :count) == 1
    end

    test "a commit another checkpoint references is never deleted (the FK cascade)", %{a: a, b: b} do
      shared = commit(a, "updates", -600)
      commit(a, "updates", -550, checkpoint: true)
      # b's checkpoint points at a's old commit (another basis anchored on it).
      Repo.insert!(%Checkpoint{
        organization_scope_id: b.organization_scope_id,
        mission_id: b.mission_id,
        partition_id: b.partition_id,
        runtime_basis_sha256: b.runtime_basis_sha256,
        version: 1,
        commit_sequence: shared.commit_sequence,
        integrity_sha256: "x"
      })

      live_run()

      refute gone?(shared)
      assert Repo.aggregate(Checkpoint, :count) == 2
    end
  end

  describe "an open pass is never touched" do
    test "commits arriving under 2 min apart keep the partition out of every tick", %{a: a} do
      # A pass of 10 min, one commit a minute; ticks every 5 min during it never see it quiet.
      old = commit(a, "updates", -900)

      for minute <- -10..-1//1 do
        commit(a, "updates", minute * 60, checkpoint: minute == -1)
      end

      for tick_at <- [-420, -120, 0] do
        assert live_run(now: DateTime.add(@now, tick_at, :second)) == []
        refute gone?(old)
      end

      # Two minutes after the pass ends, it is quiet and retired.
      assert [%{rows: 10}] = live_run(now: DateTime.add(@now, 121, :second))
      assert gone?(old)
    end

    test "a pass that starts mid-run stops the run at its next batch", %{a: a} do
      for s <- -900..-800//10, do: commit(a, "updates", s)
      commit(a, "updates", -700, checkpoint: true)
      cutoff = DateTime.add(@now, -120, :second)
      [partition] = CommitRetirement.quiet_partitions(cutoff)

      # The pass's first commit lands after the partition was listed.
      commit(a, "updates", 0, checkpoint: true)

      assert %{rows: 0, stopped: :done} = CommitRetirement.retire(partition, cutoff, pause_ms: 0)
    end
  end

  test "batches are bounded; the next tick carries on", %{a: a} do
    for s <- -900..-790//10, do: commit(a, "updates", s)
    commit(a, "updates", -700, checkpoint: true)

    assert [%{rows: 10, batches: 2, stopped: :batch_limit}] =
             live_run(batch_size: 5, max_batches: 2)

    assert [%{rows: 2, batches: 1, stopped: :done}] = live_run(batch_size: 5, max_batches: 2)
    assert live_run(batch_size: 5, max_batches: 2) == []
  end

  test ":dry counts what it would retire and deletes nothing (the default mode)", %{a: a} do
    u1 = commit(a, "updates", -600)
    commit(a, "updates", -550, checkpoint: true)

    assert [%{mode: :dry, rows: 1, batches: 0}] = run(mode: :dry)
    refute gone?(u1)
    assert run(mode: :off) == []
    refute gone?(u1)
  end

  test "the mode defaults to :dry; the environment can set it at a restart" do
    previous = System.get_env("CADENCE_SEMANTIC_COMMIT_RETIREMENT")
    on_exit(fn -> restore_env(previous) end)

    System.delete_env("CADENCE_SEMANTIC_COMMIT_RETIREMENT")
    assert SemanticCommitRetirement.mode([]) == :dry

    for {value, mode} <- [{"live", :live}, {"off", :off}, {"dry", :dry}, {"bogus", :dry}] do
      System.put_env("CADENCE_SEMANTIC_COMMIT_RETIREMENT", value)
      assert SemanticCommitRetirement.mode([]) == mode
    end

    assert SemanticCommitRetirement.mode(mode: :live) == :live
  end

  test "a run stops when the checkpoint count drops", %{a: a} do
    for s <- -900..-790//10, do: commit(a, "updates", s)
    commit(a, "updates", -700, checkpoint: true)
    [partition] = CommitRetirement.quiet_partitions(DateTime.add(@now, -120, :second))
    counts = :counters.new(1, [])

    # The count reads 1 at the start, then 0 after the first batch.
    count = fn ->
      :counters.add(counts, 1, 1)
      if :counters.get(counts, 1) == 1, do: 1, else: 0
    end

    assert %{rows: 5, batches: 1, stopped: :checkpoint_count_dropped} =
             CommitRetirement.retire(partition, DateTime.add(@now, -120, :second),
               batch_size: 5,
               pause_ms: 0,
               checkpoint_count: count
             )
  end

  test "it refuses while another table references the commits", %{a: a} do
    u1 = commit(a, "updates", -600)
    commit(a, "updates", -550, checkpoint: true)
    assert CommitRetirement.unexpected_foreign_keys() == []

    Repo.query!(
      "CREATE TABLE retirement_test_ref (s bigint REFERENCES semantic_runtime_commits (commit_sequence))"
    )

    assert {:refused, ["retirement_test_ref " <> _constraint]} = run(mode: :live)
    refute gone?(u1)
  end

  test "recovery still restores from the checkpoint after a run", %{a: a} do
    for s <- -900..-800//10, do: commit(a, "updates", s)
    checkpointed = commit(a, "updates", -700, checkpoint: true)

    assert [%{rows: 11}] = live_run()

    checkpoint = Repo.get_by!(Checkpoint, Map.to_list(a))
    seq = checkpointed.commit_sequence
    assert {:hit, %State{}, ^seq} = Checkpoint.restore(checkpoint, seq)
  end

  test "production roots run it after each pass; test roots built with new!/1 don't", %{a: a} do
    assert ProcessNamespace.default().semantic_commit_retirement ==
             SemanticCommitRetirement

    namespace =
      ProcessNamespace.new!(
        root_supervisor: :r,
        registry: :g,
        mission_supervisor: :m,
        mission_recovery: :mr,
        contact_fact_consumer: :c,
        runtime_fact_consumer: :rf
      )

    assert namespace.semantic_commit_retirement == nil

    u1 = commit(a, "updates", -600)
    commit(a, "updates", -550, checkpoint: true)

    # A started worker sweeps on demand (no tick fires: tick_ms 0), in :dry here.
    pid =
      start_supervised!(
        {SemanticCommitRetirement, name: :retirement_under_test, tick_ms: 0, mode: :dry}
      )

    Sandbox.allow(Repo, self(), pid)
    assert is_list(SemanticCommitRetirement.run_now(:retirement_under_test))
    refute gone?(u1)
  end

  defp live_run(opts \\ []), do: run(Keyword.merge([mode: :live], opts))

  defp run(opts) do
    SemanticCommitRetirement.run(Keyword.merge([now: @now, pause_ms: 0], opts))
  end

  defp partition(suffix) do
    %{
      organization_scope_id: "org-retire",
      mission_id: "mission-retire",
      partition_id: "partition-" <> suffix,
      runtime_basis_sha256: "basis-" <> suffix
    }
  end

  defp commit(partition, kind, seconds, opts \\ []) do
    # The writer fence: every commit chains from its partition's head (epoch 1).
    predecessor = head_sequence(partition)

    row =
      partition
      |> Map.merge(%{
        commit_id: "commit-#{System.unique_integer([:positive])}",
        organization_id: partition.organization_scope_id,
        mission_model_revision_id: "revision-1",
        ownership_epoch: 1,
        predecessor_sequence: predecessor,
        input_term: Terms.encode({:updates, []}),
        result_term: Terms.encode(nil),
        state_term: Terms.encode(%State{}),
        input_kind: kind || "updates",
        inserted_at: DateTime.add(@now, seconds, :second)
      })
      |> CommitRow.changeset()
      |> Repo.insert!()

    # A legacy (pre-input_kind) commit: NULL kind.
    row =
      if is_nil(kind) do
        Repo.update_all(where(CommitRow, commit_sequence: ^row.commit_sequence),
          set: [input_kind: nil]
        )

        %{row | input_kind: nil}
      else
        row
      end

    if Keyword.get(opts, :checkpoint, false), do: Checkpoint.publish(row)
    row
  end

  defp head_sequence(partition) do
    keys = Map.take(partition, [:organization_scope_id, :mission_id, :partition_id])

    Repo.query!(
      """
      INSERT INTO semantic_runtime_heads
        (organization_scope_id, mission_id, partition_id, runtime_basis_sha256, generation,
         ownership_epoch, commit_sequence)
      VALUES ($1, $2, $3, $4, 1, 1, 0)
      ON CONFLICT DO NOTHING
      """,
      [
        keys.organization_scope_id,
        keys.mission_id,
        keys.partition_id,
        partition.runtime_basis_sha256
      ]
    )

    %{rows: [[sequence]]} =
      Repo.query!(
        """
        SELECT commit_sequence FROM semantic_runtime_heads
        WHERE organization_scope_id = $1 AND mission_id = $2 AND partition_id = $3
        """,
        [keys.organization_scope_id, keys.mission_id, keys.partition_id]
      )

    sequence
  end

  defp restore_env(nil), do: System.delete_env("CADENCE_SEMANTIC_COMMIT_RETIREMENT")
  defp restore_env(value), do: System.put_env("CADENCE_SEMANTIC_COMMIT_RETIREMENT", value)

  defp gone?(%CommitRow{commit_sequence: seq}), do: is_nil(Repo.get(CommitRow, seq))
end
