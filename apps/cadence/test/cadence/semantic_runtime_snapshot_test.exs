defmodule Cadence.SemanticRuntimeSnapshotTest do
  use Cadence.DataCase, async: false

  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, Snapshot, State, Store}
  alias Cadence.TestSupport.SemanticRuntimeFixture, as: Fixture

  @at ~U[2026-08-12 12:00:00Z]

  setup do
    {spec, input_id} = Fixture.runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "snapshot"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    {:ok, empty, writer} = Store.recover_writer(spec, key, plan)
    %{spec: spec, input_id: input_id, key: key, plan: plan, empty: empty, writer: writer}
  end

  defp input(input_id, n), do: Fixture.update("snap:#{n}", input_id, n * n, DateTime.add(@at, n))

  # Processes inputs 1..n from `state` in memory (no commit log).
  defp run(state, input_id, plan, range) do
    Enum.reduce(range, {state, []}, fn n, {state, results} ->
      {:ok, result, next} = SemanticRuntime.process(state, [input(input_id, n)], plan)
      {next, results ++ [result]}
    end)
  end

  test "a partition has no snapshot until one is written", %{spec: spec, key: key} do
    assert :missing = Snapshot.fetch(spec, key)
  end

  test "a snapshot round-trips the state and its stream offsets, and replaces itself in place",
       ctx do
    %{spec: spec, key: key, plan: plan, empty: empty, writer: writer, input_id: input_id} = ctx
    {state_2, _} = run(empty, input_id, plan, 1..2)
    {state_4, _} = run(state_2, input_id, plan, 3..4)

    assert :ok = Store.snapshot(spec, key, writer, state_2, %{"stream-a" => 200})
    assert {:ok, ^state_2, %{"stream-a" => 200}} = Snapshot.fetch(spec, key)

    assert :ok = Store.snapshot(spec, key, writer, state_4, %{"stream-a" => 400, "stream-b" => 7})
    assert {:ok, ^state_4, %{"stream-a" => 400, "stream-b" => 7}} = Snapshot.fetch(spec, key)
    assert Repo.aggregate(Snapshot, :count) == 1
  end

  test "a fenced writer cannot snapshot, and the newer owner's snapshot stands", ctx do
    %{spec: spec, key: key, plan: plan, empty: empty, writer: old_writer, input_id: input_id} =
      ctx

    {state, _} = run(empty, input_id, plan, 1..2)

    # A new owner takes the partition: the old writer is fenced.
    assert {:ok, _state, writer} = Store.recover_writer(spec, key, plan)
    assert :ok = Store.snapshot(spec, key, writer, state, %{"stream-a" => 10})

    assert {:error, :semantic_runtime_fenced} =
             Store.snapshot(spec, key, old_writer, empty, %{"stream-a" => 0})

    assert {:ok, ^state, %{"stream-a" => 10}} = Snapshot.fetch(spec, key)
  end

  test "a damaged or incompatible snapshot reads as invalid, never as state", ctx do
    %{spec: spec, key: key, empty: empty, writer: writer} = ctx
    assert :ok = Store.snapshot(spec, key, writer, empty, %{"stream-a" => 1})

    Repo.update_all(Snapshot, set: [resume: %{"stream-a" => 999}])
    assert {:invalid, :integrity} = Snapshot.fetch(spec, key)

    assert :ok = Store.snapshot(spec, key, writer, empty, %{"stream-a" => 1})
    Repo.update_all(Snapshot, set: [version: 0])
    assert {:invalid, :incompatible_version} = Snapshot.fetch(spec, key)
  end

  # The crash test for the snapshot design (#692): the state a recovery builds from the snapshot
  # plus a replay of the journal from the snapshot's offsets is the state, and the results, an
  # uninterrupted run produced. Equal results are equal effect ids, so the replay repeats nothing
  # (the effect ids derive from the update ids, #476/#480).
  test "snapshot plus replay of the journal from its offsets equals the uninterrupted run", ctx do
    %{spec: spec, key: key, plan: plan, empty: empty, writer: writer, input_id: input_id} = ctx

    {uninterrupted, results} = run(empty, input_id, plan, 1..6)

    # Journal offsets: input n sits at [100n, 100n + 100). The snapshot covers inputs 1..3.
    {state_3, _} = run(empty, input_id, plan, 1..3)
    assert :ok = Store.snapshot(spec, key, writer, state_3, %{"stream-a" => 400})

    # The crash: inputs 4..5 were processed (and projected) before it, input 6 not yet. Recovery
    # reads the snapshot and replays what the journal still holds from offset 400: inputs 4..6.
    assert {:ok, restored, %{"stream-a" => 400}} = Snapshot.fetch(spec, key)
    assert restored == state_3

    {recovered, replayed} = run(restored, input_id, plan, 4..6)

    assert recovered == uninterrupted
    assert replayed == Enum.drop(results, 3)
    # Six inputs and their six derived updates: nothing applied twice.
    assert %State{sequence: 12} = recovered
  end
end
