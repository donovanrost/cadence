defmodule Cadence.Runtime.PartitionOwner.SemanticSnapshotsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.PartitionOwner.SemanticSnapshots
  alias Cadence.Runtime.SemanticSnapshotNotifier
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, Snapshot, Store}
  alias Cadence.TestSupport.SemanticRuntimeFixture, as: Fixture

  @stream "snapshots-stream"

  setup do
    {spec, input_id} = Fixture.runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "cadence-snapshots"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    {:ok, empty, writer, _resume} = Store.recover(spec, key)

    state = %{
      mission_id: spec.mission_id,
      active_activation: spec,
      partition_key: key,
      persist_runtime_records?: true,
      semantic_state: empty,
      semantic_writer: writer
    }

    %{
      state: Map.merge(state, SemanticSnapshots.init(interval_ms: 60_000, idle_ms: 60_000)),
      spec: spec,
      key: key,
      plan: plan,
      input_id: input_id
    }
  end

  # A batch result as the partition replies it: the stream, its resume offset, its end.
  defp result(resume, end_offset) do
    %{
      resume_offset: resume,
      raw_evidence: %{
        metadata: %{"journal_stream_id" => @stream, "journal_end_offset" => end_offset}
      }
    }
  end

  defp process(state, ctx, n) do
    input = Fixture.update("own:#{n}", ctx.input_id, n, DateTime.add(~U[2026-08-12 12:00:00Z], n))
    {:ok, _result, next} = SemanticRuntime.process(state.semantic_state, [input], ctx.plan)
    %{state | semantic_state: next}
  end

  test "nothing is snapshotted until the state changed, and not before the interval or idle time",
       %{state: state, spec: spec, key: key} = ctx do
    assert {:ok, ^state} = SemanticSnapshots.tick(state)
    assert :missing = Snapshot.fetch(spec, key)

    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))
    assert state.semantic_dirty?
    assert state.semantic_resume == %{@stream => 90}

    # Dirty, but neither 60 s since the last snapshot nor 60 s idle.
    assert {:ok, ^state} = SemanticSnapshots.tick(state)
    assert :missing = Snapshot.fetch(spec, key)
  end

  test "an idle partition snapshots its state and offsets, and tells the stream's consumer",
       %{state: state, spec: spec, key: key} = ctx do
    SemanticSnapshotNotifier.subscribe(@stream)
    state = %{state | semantic_snapshot_config: [interval_ms: 60_000, idle_ms: 0, tick_ms: nil]}
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))

    assert {:ok, state} = SemanticSnapshots.tick(state)

    refute state.semantic_dirty?
    assert {:ok, stored, %{@stream => 90}} = Snapshot.fetch(spec, key)
    assert stored == state.semantic_state
    partition = PartitionKey.identifier(key)
    assert_receive {:semantic_snapshot_durable, ^partition, @stream, 90}

    # Clean: no second snapshot, no second notice.
    assert {:ok, ^state} = SemanticSnapshots.tick(state)
    refute_receive {:semantic_snapshot_durable, _, _, _}, 20
  end

  test "the interval alone makes a busy partition snapshot",
       %{state: state, spec: spec, key: key} = ctx do
    state = %{state | semantic_snapshot_config: [interval_ms: 0, idle_ms: 60_000, tick_ms: nil]}
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))

    assert {:ok, %{semantic_dirty?: false}} = SemanticSnapshots.tick(state)
    assert {:ok, _state, %{@stream => 90}} = Snapshot.fetch(spec, key)
  end

  test "a stopping partition flushes what the cadence has not snapshotted",
       %{state: state, spec: spec, key: key} = ctx do
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))
    assert %{semantic_dirty?: false} = SemanticSnapshots.flush(state)
    assert {:ok, _state, %{@stream => 90}} = Snapshot.fetch(spec, key)

    clean = SemanticSnapshots.flush(%{state | semantic_dirty?: false})
    assert clean.semantic_dirty? == false
  end

  test "a stopping partition snapshots, then tells its streams it gates no longer",
       %{state: state, spec: spec, key: key} = ctx do
    SemanticSnapshotNotifier.subscribe(@stream)
    partition = PartitionKey.identifier(key)
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))

    assert %{semantic_dirty?: false} = SemanticSnapshots.stop(state)
    assert {:ok, _state, %{@stream => 90}} = Snapshot.fetch(spec, key)
    assert_receive {:semantic_snapshot_durable, ^partition, @stream, 90}
    assert_receive {:semantic_snapshot_stopped, ^partition, @stream}

    # Nothing unsnapshotted: it still says so.
    assert %{semantic_dirty?: false} = SemanticSnapshots.stop(%{state | semantic_dirty?: false})
    assert_receive {:semantic_snapshot_stopped, ^partition, @stream}
  end

  test "a stopping partition whose final snapshot fails keeps gating",
       %{state: state, spec: spec, key: key, plan: plan} = ctx do
    SemanticSnapshotNotifier.subscribe(@stream)
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))
    assert {:ok, _state, _writer, _resume} = Store.recover(spec, key)

    assert %{semantic_dirty?: true} = SemanticSnapshots.stop(state)
    refute_receive {:semantic_snapshot_stopped, _, _}, 20
  end

  test "frames the recovered snapshot already includes are skipped, and only those", %{
    state: state
  } do
    at = ~U[2026-11-26 12:00:00Z]
    recovered = Map.put(state, :semantic_replay_floor, %{@stream => 400})
    frame = fn stream, offset -> %{journal_frame: {stream, offset, at}} end

    assert SemanticSnapshots.skip_replayed?(recovered, frame.(@stream, 399))
    refute SemanticSnapshots.skip_replayed?(recovered, frame.(@stream, 400))
    refute SemanticSnapshots.skip_replayed?(recovered, frame.(@stream, 900))
    # Another stream, or no journal frame at all, is never skipped.
    refute SemanticSnapshots.skip_replayed?(recovered, frame.("another", 0))
    refute SemanticSnapshots.skip_replayed?(recovered, %{journal_frame: nil})
    # An owner that recovered nothing skips nothing.
    refute SemanticSnapshots.skip_replayed?(state, frame.(@stream, 0))
  end

  test "a timer firing makes a gated partition's state due for a snapshot", %{state: state} do
    assert %{semantic_dirty?: true} = SemanticSnapshots.touch(state)

    ungated = %{state | semantic_writer: nil}
    assert ^ungated = SemanticSnapshots.touch(ungated)
  end

  test "a recovering partition tells the consumers it gated which offsets it recovered", %{
    state: state,
    key: key
  } do
    partition = PartitionKey.identifier(key)
    SemanticSnapshotNotifier.subscribe_partition(partition)
    recovered = Map.put(state, :semantic_replay_floor, %{@stream => 400})

    assert :ok = SemanticSnapshots.announce_recovery(recovered)
    assert_receive {:semantic_partition_recovered, ^partition, %{@stream => 400}}

    # No semantic writer, nothing recovered, nothing announced.
    assert :ok = SemanticSnapshots.announce_recovery(%{recovered | semantic_writer: nil})
    refute_receive {:semantic_partition_recovered, _, _}, 20
  end

  test "a resume offset never moves back, and falls back to the batch's end", %{state: state} do
    state = SemanticSnapshots.track(state, result(nil, 100))
    assert state.semantic_resume == %{@stream => 100}

    assert SemanticSnapshots.track(state, result(60, 120)).semantic_resume == %{@stream => 100}
    assert SemanticSnapshots.track(state, result(130, 150)).semantic_resume == %{@stream => 130}
  end

  test "a fenced owner's snapshot fails: it stays dirty and tells no one",
       %{state: state, spec: spec, key: key, plan: plan} = ctx do
    SemanticSnapshotNotifier.subscribe(@stream)
    state = %{state | semantic_snapshot_config: [interval_ms: 0, idle_ms: 0, tick_ms: nil]}
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))

    # Another owner takes the partition.
    assert {:ok, _state, _writer, _resume} = Store.recover(spec, key)

    assert {:fenced, %{semantic_dirty?: true}} = SemanticSnapshots.tick(state)
    assert :missing = Snapshot.fetch(spec, key)
    refute_receive {:semantic_snapshot_durable, _, _, _}, 20
  end

  test "a partition with no semantic writer is neither tracked nor gating", %{state: state} do
    for ungated <- [%{state | semantic_writer: nil}, %{state | persist_runtime_records?: false}] do
      refute SemanticSnapshots.gated?(ungated)
      assert ^ungated = SemanticSnapshots.track(ungated, result(90, 100))
      assert SemanticSnapshots.partition(ungated, result(90, 100)) == nil
      assert ^ungated = SemanticSnapshots.flush(ungated)
    end

    assert SemanticSnapshots.partition(state, result(90, 100)) ==
             "source_endpoint:cadence-snapshots"
  end
end
