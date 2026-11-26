defmodule Cadence.SemanticRuntimeStoreTest do
  @moduledoc """
  Ownership and recovery of a partition's semantic runtime (#692): taking the partition fences the
  previous owner, and recovery is the last snapshot.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, Snapshot, State, Store}
  alias Cadence.TestSupport.SemanticRuntimeFixture, as: Fixture

  setup do
    {spec, input_id} = Fixture.runtime_spec()

    key =
      PartitionKey.new(%{
        affinity: :source_endpoint,
        value: "store-#{System.unique_integer([:positive])}"
      })

    %{spec: spec, input_id: input_id, key: key, plan: PlanDecoder.decode(spec.runtime_plans)}
  end

  defp state_after(plan, input_id, count) do
    Enum.reduce(1..count, %State{}, fn n, state ->
      input = Fixture.update("store:#{n}", input_id, n, DateTime.add(~U[2026-08-12 12:00:00Z], n))
      {:ok, _result, next} = SemanticRuntime.process(state, [input], plan)
      next
    end)
  end

  defp observe_recoveries do
    id = {__MODULE__, self()}

    :telemetry.attach(
      id,
      [:cadence, :runtime, :partition, :snapshot_recovery],
      fn _, _, metadata, pid -> send(pid, {:recovery, metadata.outcome}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  test "a partition with no snapshot recovers empty, on a new epoch each time", %{
    spec: spec,
    key: key
  } do
    observe_recoveries()

    assert {:ok, %State{} = empty, first, %{}} = Store.recover(spec, key)
    assert empty == %State{}
    assert_receive {:recovery, :missing}

    assert {:ok, %State{}, second, %{}} = Store.recover(spec, key)
    assert second.epoch == first.epoch + 1
  end

  test "taking the partition fences the previous owner, whose snapshot writes nothing", ctx do
    %{spec: spec, key: key, plan: plan, input_id: input_id} = ctx
    {:ok, _empty, old, _} = Store.recover(spec, key)
    state = state_after(plan, input_id, 2)

    assert :ok = Store.snapshot(spec, key, old, state, %{"s" => 10})
    {:ok, ^state, new, %{"s" => 10}} = Store.recover(spec, key)

    assert {:error, :semantic_runtime_fenced} =
             Store.snapshot(spec, key, old, %State{}, %{"s" => 0})

    assert {:ok, ^state, %{"s" => 10}} = Snapshot.fetch(spec, key)
    assert :ok = Store.snapshot(spec, key, new, state, %{"s" => 20})
  end

  test "recovery is the last snapshot: its state and its stream offsets", ctx do
    %{spec: spec, key: key, plan: plan, input_id: input_id} = ctx
    observe_recoveries()
    {:ok, _empty, writer, _} = Store.recover(spec, key)
    assert_receive {:recovery, :missing}

    early = state_after(plan, input_id, 2)
    late = state_after(plan, input_id, 4)
    assert :ok = Store.snapshot(spec, key, writer, early, %{"s" => 100})
    assert :ok = Store.snapshot(spec, key, writer, late, %{"s" => 200, "t" => 7})

    assert {:ok, ^late, _writer, %{"s" => 200, "t" => 7}} = Store.recover(spec, key)
    assert_receive {:recovery, :hit}
  end

  test "a damaged or incompatible snapshot starts the partition empty, and is replaced", ctx do
    %{spec: spec, key: key, plan: plan, input_id: input_id} = ctx
    observe_recoveries()
    {:ok, _empty, writer, _} = Store.recover(spec, key)
    assert_receive {:recovery, :missing}
    state = state_after(plan, input_id, 2)
    assert :ok = Store.snapshot(spec, key, writer, state, %{"s" => 100})

    Repo.update_all(Snapshot, set: [version: 0])
    assert {:ok, %State{} = empty, writer, %{}} = Store.recover(spec, key)
    assert empty == %State{}
    assert_receive {:recovery, :invalid}

    assert :ok = Store.snapshot(spec, key, writer, state, %{"s" => 100})
    assert {:ok, ^state, _writer, %{"s" => 100}} = Store.recover(spec, key)
  end

  test "ownership tokens cannot cross partitions", %{spec: spec, key: key} do
    other = PartitionKey.new(%{affinity: :source_endpoint, value: "other-#{key.value}"})
    {:ok, _, writer, _} = Store.recover(spec, key)
    {:ok, _, _other_writer, _} = Store.recover(spec, other)

    assert {:error, :semantic_runtime_fenced} =
             Store.snapshot(spec, other, writer, %State{}, %{"s" => 1})

    assert :missing = Snapshot.fetch(spec, other)
  end

  test "a snapshot is per tenant and runtime basis", %{spec: spec, key: key} = ctx do
    {:ok, _, writer, _} = Store.recover(spec, key)
    state = state_after(ctx.plan, ctx.input_id, 2)
    assert :ok = Store.snapshot(spec, key, writer, state, %{"s" => 5})

    assert :missing = Snapshot.fetch(%{spec | runtime_basis_sha256: "another-basis"}, key)
    assert :missing = Snapshot.fetch(%{spec | organization_id: "another-org"}, key)
    assert {:ok, ^state, %{"s" => 5}} = Snapshot.fetch(spec, key)
  end

  test "a newer generation fences an old basis and cannot be claimed by an old generation", ctx do
    %{spec: spec, key: key} = ctx
    assert {:ok, _, writer, _} = Store.recover(spec, key)
    next = %{spec | generation: spec.generation + 1, runtime_basis_sha256: "new-basis"}
    assert {:ok, %State{}, next_writer, _} = Store.recover(next, key)
    assert next_writer.epoch > writer.epoch

    assert {:error, :semantic_runtime_fenced} =
             Store.snapshot(spec, key, writer, %State{}, %{"s" => 1})

    assert {:error, :semantic_runtime_stale_generation} = Store.recover(spec, key)

    assert {:error, :semantic_runtime_generation_conflict} =
             Store.recover(%{next | runtime_basis_sha256: "conflicting-basis"}, key)
  end
end
