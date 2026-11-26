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
    {:ok, empty, writer} = Store.recover_writer(spec, key, plan)

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
    assert state == SemanticSnapshots.tick(state)
    assert :missing = Snapshot.fetch(spec, key)

    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))
    assert state.semantic_dirty?
    assert state.semantic_resume == %{@stream => 90}

    # Dirty, but neither 60 s since the last snapshot nor 60 s idle.
    assert ^state = SemanticSnapshots.tick(state)
    assert :missing = Snapshot.fetch(spec, key)
  end

  test "an idle partition snapshots its state and offsets, and tells the stream's consumer",
       %{state: state, spec: spec, key: key} = ctx do
    SemanticSnapshotNotifier.subscribe(@stream)
    state = %{state | semantic_snapshot_config: [interval_ms: 60_000, idle_ms: 0, tick_ms: nil]}
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))

    state = SemanticSnapshots.tick(state)

    refute state.semantic_dirty?
    assert {:ok, stored, %{@stream => 90}} = Snapshot.fetch(spec, key)
    assert stored == state.semantic_state
    partition = PartitionKey.identifier(key)
    assert_receive {:semantic_snapshot_durable, ^partition, @stream, 90}

    # Clean: no second snapshot, no second notice.
    assert ^state = SemanticSnapshots.tick(state)
    refute_receive {:semantic_snapshot_durable, _, _, _}, 20
  end

  test "the interval alone makes a busy partition snapshot",
       %{state: state, spec: spec, key: key} = ctx do
    state = %{state | semantic_snapshot_config: [interval_ms: 0, idle_ms: 60_000, tick_ms: nil]}
    state = state |> process(ctx, 1) |> SemanticSnapshots.track(result(90, 100))

    assert %{semantic_dirty?: false} = SemanticSnapshots.tick(state)
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
    assert {:ok, _state, _writer} = Store.recover_writer(spec, key, plan)

    assert %{semantic_dirty?: true} = SemanticSnapshots.tick(state)
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
