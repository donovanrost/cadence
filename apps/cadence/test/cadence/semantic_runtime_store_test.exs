defmodule Cadence.SemanticRuntimeStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer}
  alias Cadence.Runtime.{MissionRuntimeSpec, PartitionKey}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{Checkpoint, CommitRow, PlanDecoder, Scope, State, Store, Update}
  alias Ecto.Adapters.SQL.Sandbox

  test "commits idempotently and reconstructs state from ordered durable inputs" do
    {runtime_spec, input_id} = runtime_spec()
    partition_key = PartitionKey.new(%{affinity: :source_endpoint, value: "pobc"})
    plan = PlanDecoder.decode(runtime_spec.runtime_plans)
    assert {:ok, %State{}, writer} = Store.recover_writer(runtime_spec, partition_key, plan)
    at = ~U[2026-08-12 12:00:00Z]

    first = update("update:1", input_id, 10, at)
    second = update("update:2", input_id, 15, DateTime.add(at, 1, :second))

    assert {:ok, first_result, first_state} =
             SemanticRuntime.process(%State{}, [first], plan)

    assert {:ok, ^first_result, ^first_state, writer} =
             Store.commit(runtime_spec, partition_key, writer, [first], first_result, first_state)

    assert {:ok, ^first_result, ^first_state, writer} =
             Store.commit(runtime_spec, partition_key, writer, [first], first_result, first_state)

    assert {:ok, second_result, second_state} =
             SemanticRuntime.process(first_state, [second], plan)

    assert {:ok, ^second_result, ^second_state, writer} =
             Store.commit(
               runtime_spec,
               partition_key,
               writer,
               [second],
               second_result,
               second_state
             )

    # Retrying an older input must preserve the latest state and durable head.
    assert {:ok, ^first_result, ^second_state, ^writer} =
             Store.commit(runtime_spec, partition_key, writer, [first], first_result, first_state)

    assert {:ok, ^second_state} = Store.recover(runtime_spec, partition_key, plan)
  end

  test "retains unprojected timer results until their observation projection is acknowledged" do
    {runtime_spec, input_id} = runtime_spec()
    partition_key = PartitionKey.new(%{affinity: :source_endpoint, value: "pobc-timer"})
    plan = PlanDecoder.decode(runtime_spec.runtime_plans)
    assert {:ok, %State{}, writer} = Store.recover_writer(runtime_spec, partition_key, plan)
    at = ~U[2026-08-12 12:00:00Z]
    input = update("update:timer", input_id, 10, at)

    assert {:ok, _, state, writer} =
             Store.process(runtime_spec, partition_key, writer, %State{}, [input], plan)

    algorithm_id = plan.algorithms |> hd() |> Map.fetch!(:algorithm_id)
    timer_at = DateTime.add(at, 5, :second)

    assert {:ok, timer_result, timer_state} =
             SemanticRuntime.timer(
               state,
               Scope.new("semantic-store-mission", "spacecraft-a"),
               algorithm_id,
               timer_at,
               plan
             )

    assert {:ok, ^timer_result, ^timer_state, _writer} =
             Store.commit_timer(
               runtime_spec,
               partition_key,
               writer,
               {Scope.new("semantic-store-mission", "spacecraft-a"), algorithm_id, timer_at,
                "periodic:" <> algorithm_id},
               timer_result,
               timer_state
             )

    assert {:ok, [pending]} = Store.pending_timer_results(runtime_spec, partition_key)
    assert pending.at == timer_at
    assert pending.result == timer_result
    assert {:ok, ^timer_state, _} = Store.recover_writer(runtime_spec, partition_key, plan)
    assert {:ok, cursors} = Store.timer_cursors(runtime_spec, partition_key)
    assert cursors[pending.timer_key] == timer_at

    # Legacy metadata is decoded correctly, then backfilled during bootstrap.
    Repo.delete_all(Checkpoint)
    Repo.update_all(CommitRow, set: [input_kind: nil, timer_key: nil, timer_at: nil])
    assert {:ok, ^cursors} = Store.timer_cursors(runtime_spec, partition_key)
    assert {:ok, [^pending]} = Store.pending_timer_results(runtime_spec, partition_key)
    assert {:ok, ^timer_state, _} = Store.recover_writer(runtime_spec, partition_key, plan)
    assert {:ok, ^cursors} = Store.timer_cursors(runtime_spec, partition_key)
    assert {:ok, [^pending]} = Store.pending_timer_results(runtime_spec, partition_key)

    assert :ok =
             Store.mark_timer_projected(
               runtime_spec,
               partition_key,
               pending.timer_key,
               timer_at
             )

    assert {:ok, []} = Store.pending_timer_results(runtime_spec, partition_key)
  end

  test "recovers across cursor batches and still rejects a divergent later commit" do
    {runtime_spec, input_id} = runtime_spec()
    partition_key = PartitionKey.new(%{affinity: :source_endpoint, value: "paged-recovery"})
    plan = PlanDecoder.decode(runtime_spec.runtime_plans)
    assert {:ok, %State{}, writer} = Store.recover_writer(runtime_spec, partition_key, plan)
    at = ~U[2026-08-12 12:00:00Z]

    {final_state, _writer} =
      Enum.reduce(1..205, {%State{}, writer}, fn index, {state, writer} ->
        input = update("paged:#{index}", input_id, index, DateTime.add(at, index, :second))
        assert {:ok, result, next_state} = SemanticRuntime.process(state, [input], plan)

        assert {:ok, ^result, ^next_state, writer} =
                 Store.commit(runtime_spec, partition_key, writer, [input], result, next_state)

        {next_state, writer}
      end)

    assert {:ok, ^final_state} = Store.recover(runtime_spec, partition_key, plan)
    assert {:ok, %{}} = Store.timer_cursors(runtime_spec, partition_key)
    assert {:ok, []} = Store.pending_timer_results(runtime_spec, partition_key)

    last =
      Cadence.SemanticRuntime.CommitRow
      |> order_by([row], desc: row.commit_sequence)
      |> limit(1)
      |> Repo.one!()

    last
    |> Ecto.Changeset.change(state_term: :erlang.term_to_binary(%State{}))
    |> Repo.update!()

    assert {:error, {:semantic_runtime_replay_diverged, commit_id}} =
             Store.recover(runtime_spec, partition_key, plan)

    assert commit_id == last.commit_id
  end

  test "an old epoch cannot append even at the same predecessor, and recovers before retrying" do
    {spec, input_id} = runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "fenced"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    assert {:ok, empty, old_writer} = Store.recover_writer(spec, key, plan)
    assert {:ok, ^empty, writer} = Store.recover_writer(spec, key, plan)
    input = update("fenced:1", input_id, 10, ~U[2026-08-12 12:00:00Z])
    assert {:ok, result, state} = SemanticRuntime.process(empty, [input], plan)

    assert {:error, :semantic_runtime_fenced} =
             Store.commit(spec, key, old_writer, [input], result, state)

    assert Repo.aggregate(Cadence.SemanticRuntime.CommitRow, :count) == 0

    assert {:ok, ^result, ^state, writer} =
             Store.commit(spec, key, writer, [input], result, state)

    second = update("fenced:2", input_id, 15, ~U[2026-08-12 12:00:01Z])
    assert {:ok, expected_result, expected_state} = SemanticRuntime.process(state, [second], plan)
    observe_checkpoints()

    assert {:ok, ^expected_result, ^expected_state, replacement} =
             Store.process(spec, key, old_writer, empty, [second], plan)

    assert_receive {:checkpoint, %{replayed_commits: 0}, %{outcome: :hit}}
    assert replacement.epoch > writer.epoch
    assert {:ok, ^expected_state} = Store.recover(spec, key, plan)

    assert {:error, :semantic_runtime_fenced} =
             Store.commit(spec, key, writer, [input], result, state)
  end

  test "a current epoch cannot append from an outdated predecessor, including timers" do
    {spec, input_id} = runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "predecessor"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    assert {:ok, empty, writer} = Store.recover_writer(spec, key, plan)
    input = update("predecessor:1", input_id, 10, ~U[2026-08-12 12:00:00Z])

    assert {:ok, result, state, next_writer} =
             Store.process(spec, key, writer, empty, [input], plan)

    assert {:error, :semantic_runtime_stale_predecessor} =
             Store.commit(spec, key, writer, [input], result, state)

    assert {:error, :semantic_runtime_stale_predecessor} =
             Store.commit_timer(
               spec,
               key,
               writer,
               {Scope.new(spec.mission_id, nil), "algorithm", ~U[2026-08-12 12:00:05Z], "timer"},
               result,
               state
             )

    assert next_writer.epoch == writer.epoch
    assert Repo.aggregate(Cadence.SemanticRuntime.CommitRow, :count) == 1
  end

  test "a fenced timer recovers missing inputs and duplicate timers preserve later state" do
    {spec, input_id} = runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "timer-transfer"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    assert {:ok, empty, old_writer} = Store.recover_writer(spec, key, plan)
    assert {:ok, ^empty, writer} = Store.recover_writer(spec, key, plan)
    first = update("timer-transfer:1", input_id, 10, ~U[2026-08-12 12:00:00Z])
    assert {:ok, _, state, _} = Store.process(spec, key, writer, empty, [first], plan)
    algorithm_id = hd(plan.algorithms).algorithm_id
    scope = Scope.new(spec.mission_id, "spacecraft-a")
    at = ~U[2026-08-12 12:00:05Z]

    assert {:ok, expected, expected_state} =
             SemanticRuntime.timer(state, scope, algorithm_id, at, plan)

    observe_checkpoints()

    assert {:ok, ^expected, ^expected_state, timer_writer} =
             Store.timer(spec, key, old_writer, empty, {scope, algorithm_id, at, "timer"}, plan)

    assert_receive {:checkpoint, %{replayed_commits: 0}, %{outcome: :hit}}
    second = update("timer-transfer:2", input_id, 15, ~U[2026-08-12 12:00:06Z])

    assert {:ok, _, latest, latest_writer} =
             Store.process(spec, key, timer_writer, expected_state, [second], plan)

    assert {:ok, ^expected, ^latest, ^latest_writer} =
             Store.timer(
               spec,
               key,
               latest_writer,
               latest,
               {scope, algorithm_id, at, "timer"},
               plan
             )

    assert {:ok, ^latest} = Store.recover(spec, key, plan)
  end

  test "ownership tokens cannot cross partitions with coincident epochs and empty heads" do
    {spec, input_id} = runtime_spec()
    first = PartitionKey.new(%{affinity: :source_endpoint, value: "first"})
    second = PartitionKey.new(%{affinity: :source_endpoint, value: "second"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    assert {:ok, empty, first_writer} = Store.recover_writer(spec, first, plan)
    assert {:ok, ^empty, second_writer} = Store.recover_writer(spec, second, plan)
    assert first_writer.epoch == second_writer.epoch
    input = update("cross-partition", input_id, 10, ~U[2026-08-12 12:00:00Z])
    assert {:ok, result, state} = SemanticRuntime.process(empty, [input], plan)

    assert {:error, :semantic_runtime_fenced} =
             Store.commit(spec, second, first_writer, [input], result, state)

    assert Repo.aggregate(Cadence.SemanticRuntime.CommitRow, :count) == 0

    assert {:error, :semantic_runtime_fenced} =
             Store.process(spec, second, first_writer, empty, [input], plan)

    # Reject the foreign token before acquiring an epoch in the second partition.
    assert {:ok, ^result, ^state, _} =
             Store.commit(spec, second, second_writer, [input], result, state)
  end

  test "a newer generation fences an old basis and cannot be claimed by an old generation" do
    {spec, _} = runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "generation"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    assert {:ok, _, writer} = Store.recover_writer(spec, key, plan)
    next = %{spec | generation: spec.generation + 1, runtime_basis_sha256: "new-basis"}
    assert {:ok, %State{}, next_writer} = Store.recover_writer(next, key, plan)
    assert next_writer.epoch > writer.epoch
    assert {:error, :semantic_runtime_stale_generation} = Store.recover_writer(spec, key, plan)

    assert {:error, :semantic_runtime_generation_conflict} =
             Store.recover_writer(%{next | runtime_basis_sha256: "conflicting-basis"}, key, plan)
  end

  test "the database rejects legacy inserts that omit ownership, even outside Store" do
    {spec, input_id} = runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "legacy"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    assert {:ok, empty, writer} = Store.recover_writer(spec, key, plan)
    input = update("legacy:1", input_id, 10, ~U[2026-08-12 12:00:00Z])
    assert {:ok, _, _, _} = Store.process(spec, key, writer, empty, [input], plan)
    row = Repo.one!(Cadence.SemanticRuntime.CommitRow)

    legacy = %{
      row
      | commit_sequence: nil,
        commit_id: "legacy-write",
        ownership_epoch: nil,
        predecessor_sequence: nil
    }

    assert_raise Ecto.ConstraintError, ~r/semantic_runtime_writer_fence/, fn ->
      Repo.insert!(Ecto.put_meta(legacy, state: :built), mode: :savepoint)
    end

    assert Repo.aggregate(Cadence.SemanticRuntime.CommitRow, :count) == 1
  end

  test "concurrent database transactions can append only one successor to a head" do
    {spec, input_id} = runtime_spec()

    key =
      PartitionKey.new(%{
        affinity: :source_endpoint,
        value: "concurrent-#{System.unique_integer([:positive])}"
      })

    plan = PlanDecoder.decode(spec.runtime_plans)
    sandbox = Sandbox

    on_exit(fn ->
      sandbox.unboxed_run(Repo, fn ->
        id = PartitionKey.identifier(key)

        Repo.delete_all(
          from(row in Cadence.SemanticRuntime.CommitRow, where: row.partition_id == ^id)
        )

        Repo.delete_all(
          from(row in Cadence.SemanticRuntime.HeadRow, where: row.partition_id == ^id)
        )
      end)
    end)

    {:ok, empty, writer} =
      independent(fn -> Store.recover_writer(spec, key, plan) end) |> Task.await()

    parent = self()

    tasks =
      for index <- 1..2 do
        Task.async(fn ->
          sandbox.unboxed_run(Repo, fn ->
            input = update("concurrent:#{index}", input_id, index, ~U[2026-08-12 12:00:00Z])
            {:ok, result, state} = SemanticRuntime.process(empty, [input], plan)
            send(parent, {:ready, self()})

            receive do
              :commit -> Store.commit(spec, key, writer, [input], result, state)
            after
              5_000 -> raise "commit barrier not released"
            end
          end)
        end)
      end

    ready =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(ready, &send(&1, :commit))

    outcomes = Enum.map(tasks, &Task.await/1)
    assert Enum.count(outcomes, &match?({:ok, _, _, _}, &1)) == 1, inspect(outcomes)
    assert Enum.count(outcomes, &match?({:error, :semantic_runtime_stale_predecessor}, &1)) == 1

    assert {:ok, %State{sequence: sequence}} =
             independent(fn -> Store.recover(spec, key, plan) end) |> Task.await()

    assert sequence > 0
  end

  defp independent(operation) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, operation) end)
  end

  test "restart restores a durable checkpoint without replay and still audits the entire history" do
    {spec, key, plan, state, writer} = checkpoint_history()
    observe_checkpoints()
    assert Repo.one!(Checkpoint).commit_sequence == writer.commit_sequence
    assert {:ok, ^state, _} = Store.recover_writer(spec, key, plan)
    assert_receive {:checkpoint, %{replayed_commits: 0}, %{outcome: :hit}}

    first = CommitRow |> order_by([r], r.commit_sequence) |> limit(1) |> Repo.one!()
    Repo.update!(Ecto.Changeset.change(first, result_term: :erlang.term_to_binary(%{})))
    assert {:error, {:semantic_runtime_replay_diverged, id}} = Store.recover(spec, key, plan)
    assert id == first.commit_id
  end

  test "an older checkpoint verifies and backfills the suffix before publishing the new head" do
    {spec, key, plan, state, writer} = checkpoint_history()
    observe_checkpoints()
    checkpoint = Repo.one!(Checkpoint)
    first = CommitRow |> order_by([r], r.commit_sequence) |> limit(1) |> Repo.one!()
    # Model an older binary appending after the checkpoint, including NULL metadata.
    Checkpoint.publish(first)

    from(r in CommitRow, where: r.commit_sequence == ^writer.commit_sequence)
    |> Repo.update_all(set: [input_kind: nil])

    assert {:ok, ^state, _} = Store.recover_writer(spec, key, plan)
    assert_receive {:checkpoint, %{replayed_commits: 1}, %{outcome: :hit}}
    assert Repo.one!(Checkpoint) == checkpoint
    assert Repo.get!(CommitRow, writer.commit_sequence).input_kind == "updates"
  end

  test "missing, incompatible and corrupt checkpoints fall back to verified full recovery" do
    {spec, key, plan, state, _} = checkpoint_history()
    observe_checkpoints()
    Repo.delete_all(Checkpoint)
    Repo.update_all(CommitRow, set: [input_kind: nil])
    assert {:ok, ^state, _} = Store.recover_writer(spec, key, plan)
    assert_receive {:checkpoint, %{replayed_commits: 2}, %{outcome: :missing}}
    assert Repo.aggregate(from(r in CommitRow, where: is_nil(r.input_kind)), :count) == 0

    Repo.update_all(Checkpoint, set: [version: 999])
    assert {:ok, ^state, _} = Store.recover_writer(spec, key, plan)
    assert_receive {:checkpoint, %{replayed_commits: 2}, %{outcome: :incompatible}}

    Repo.update_all(Checkpoint, set: [integrity_sha256: "corrupt"])
    assert {:ok, ^state, _} = Store.recover_writer(spec, key, plan)
    assert_receive {:checkpoint, %{replayed_commits: 2}, %{outcome: :invalid}}
  end

  test "warm ownership transfer verifies history when its checkpoint is missing" do
    {spec, key, plan, state, old_writer} = checkpoint_history()
    assert {:ok, ^state, writer} = Store.recover_writer(spec, key, plan)
    Repo.delete_all(Checkpoint)
    observe_checkpoints()
    input = update("warm-fallback", elem(runtime_spec(), 1), 3, ~U[2026-08-12 12:00:03Z])
    assert {:ok, result, expected} = SemanticRuntime.process(state, [input], plan)

    assert {:ok, ^result, ^expected, replacement} =
             Store.process(spec, key, old_writer, state, [input], plan)

    assert_receive {:checkpoint, %{replayed_commits: 2}, %{outcome: :missing}}
    assert replacement.epoch > writer.epoch
    assert {:ok, ^expected} = Store.recover(spec, key, plan)
  end

  test "a concurrent append after acquisition does not move the captured recovery checkpoint" do
    {spec, key, plan, state, old_writer} = checkpoint_history()
    observe_checkpoints()
    id = {:append_after_acquisition, self()}
    input = update("concurrent-checkpoint", elem(runtime_spec(), 1), 3, ~U[2026-08-12 12:00:03Z])

    :telemetry.attach(
      id,
      [:cadence, :runtime, :partition, :ownership],
      fn _, _, metadata, _ ->
        :telemetry.detach(id)
        writer = %{old_writer | epoch: metadata.ownership_epoch}
        assert {:ok, _, _, _} = Store.process(spec, key, writer, state, [input], plan)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    assert {:ok, ^state, writer} = Store.recover_writer(spec, key, plan)
    assert writer.commit_sequence == old_writer.commit_sequence
    assert Repo.one!(Checkpoint).commit_sequence > writer.commit_sequence
    assert_receive {:checkpoint, %{replayed_commits: 0}, %{outcome: :hit}}

    # The stale predecessor is still fenced, then the missing suffix is recovered.
    assert {:ok, _, latest, _} = Store.process(spec, key, writer, state, [input], plan)
    assert {:ok, ^latest} = Store.recover(spec, key, plan)
  end

  test "corrupt checkpoint state and divergent suffixes cannot become new checkpoints" do
    {spec, key, plan, _, writer} = checkpoint_history()
    latest = Repo.get!(CommitRow, writer.commit_sequence)
    first = CommitRow |> order_by([r], r.commit_sequence) |> limit(1) |> Repo.one!()
    Repo.update!(Ecto.Changeset.change(latest, state_term: :erlang.term_to_binary(%State{})))
    checkpoint = Repo.one!(Checkpoint)

    assert {:error, {:semantic_runtime_replay_diverged, _}} =
             Store.recover_writer(spec, key, plan)

    assert Repo.one!(Checkpoint) == checkpoint

    Checkpoint.publish(first)
    checkpoint = Repo.one!(Checkpoint)

    assert {:error, {:semantic_runtime_replay_diverged, _}} =
             Store.recover_writer(spec, key, plan)

    assert Repo.one!(Checkpoint) == checkpoint
  end

  test "checkpoints cannot cross tenant, partition or runtime basis boundaries" do
    {spec, key, plan, _, _} = checkpoint_history()
    other = PartitionKey.new(%{affinity: :source_endpoint, value: "other-checkpoint"})
    assert {:ok, %State{sequence: 0}, _} = Store.recover_writer(spec, other, plan)

    assert {:ok, %State{sequence: 0}, _} =
             Store.recover_writer(%{spec | organization_id: "other"}, key, plan)

    assert {:ok, %State{sequence: 0}, _} =
             Store.recover_writer(
               %{spec | generation: 2, runtime_basis_sha256: "other"},
               key,
               plan
             )

    assert Repo.aggregate(Checkpoint, :count) == 1

    # Even a mismatched pointer cannot restore another partition's state.
    Repo.update_all(Checkpoint, set: [partition_id: PartitionKey.identifier(other)])
    assert {:invalid, %State{sequence: 0}, 0} = Checkpoint.load(spec, other, 1_000_000_000)
  end

  test "commit rollback and stale writers cannot advance a checkpoint" do
    {spec, key, plan, state, writer} = checkpoint_history()
    checkpoint = Repo.one!(Checkpoint)
    input = update("rollback", elem(runtime_spec(), 1), 3, ~U[2026-08-12 12:00:03Z])

    assert {:error, :abort} =
             Repo.transaction(fn ->
               assert {:ok, _, _, _} = Store.process(spec, key, writer, state, [input], plan)
               Repo.rollback(:abort)
             end)

    assert Repo.one!(Checkpoint) == checkpoint
    assert Repo.aggregate(CommitRow, :count) == 2

    assert {:ok, ^state, _} = Store.recover_writer(spec, key, plan)
    assert {:ok, result, next} = SemanticRuntime.process(state, [input], plan)

    assert {:error, :semantic_runtime_fenced} =
             Store.commit(spec, key, writer, [input], result, next)

    assert Repo.one!(Checkpoint) == checkpoint
  end

  defp checkpoint_history do
    {spec, input_id} = runtime_spec()
    key = PartitionKey.new(%{affinity: :source_endpoint, value: "checkpoint"})
    plan = PlanDecoder.decode(spec.runtime_plans)
    {:ok, empty, writer} = Store.recover_writer(spec, key, plan)

    {state, writer} =
      Enum.reduce(1..2, {empty, writer}, fn index, {state, writer} ->
        input =
          update(
            "checkpoint:#{index}",
            input_id,
            index,
            DateTime.add(~U[2026-08-12 12:00:00Z], index)
          )

        {:ok, _, next, writer} = Store.process(spec, key, writer, state, [input], plan)
        {next, writer}
      end)

    {spec, key, plan, state, writer}
  end

  defp observe_checkpoints do
    id = {__MODULE__, self()}

    :telemetry.attach(
      id,
      [:cadence, :runtime, :partition, :checkpoint],
      fn _, measurements, metadata, pid -> send(pid, {:checkpoint, measurements, metadata}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp runtime_spec do
    input = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/input"})
    output = Declaration.new(%{kind: :parameter, qualified_name: "/parameters/output"})

    algorithm =
      Declaration.new(%{
        kind: :algorithm,
        qualified_name: "/algorithms/delta",
        references: [
          %{expected_kind: :parameter, source_ref: input.qualified_name, role: :input},
          %{expected_kind: :parameter, source_ref: output.qualified_name, role: :output}
        ],
        definition: %{
          implementation: %{kind: :expression},
          outputs: [
            %{
              parameter_id: output.semantic_id,
              qualified_name: output.qualified_name,
              expression: %{
                node:
                  {:stateful, :delta, input.semantic_id, {:parameter, input.semantic_id}, %{}},
                result_type: :number
              }
            }
          ]
        }
      })

    layer =
      Layer.new(%{
        mission_id: "semantic-store-mission",
        name: "semantic store",
        declarations: [
          %{kind: :space_system, qualified_name: "/"},
          input,
          output,
          algorithm
        ]
      })

    assert {:ok, compilation} = Compiler.compile([layer])

    binding_set =
      BindingSet.new(%{
        mission_id: layer.mission_id,
        binding_set_id: "semantic-store-binding",
        version: 1
      })

    assert {:ok, runtime_spec} =
             MissionRuntimeSpec.new(%{
               activation_id: "semantic-store-activation",
               mission_id: layer.mission_id,
               generation: 1,
               binding_set_id: binding_set.binding_set_id,
               binding_set_version: binding_set.version,
               binding_set: binding_set,
               mission_model_revision_id: compilation.revision.revision_id,
               mission_model_content_sha256: compilation.revision.content_sha256,
               runtime_plans: compilation.plans,
               activated_at: ~U[2026-08-12 12:00:00Z]
             })

    {runtime_spec, input.semantic_id}
  end

  defp update(update_id, parameter_id, value, at) do
    Update.new(%{
      update_id: update_id,
      parameter_id: parameter_id,
      qualified_name: "/parameters/input",
      value: value,
      raw_value: value,
      quality: :good,
      generation_time: at,
      receipt_time: at,
      producer_kind: :container,
      producer_id: "container:hk",
      metadata: %{mission_id: "semantic-store-mission", spacecraft_id: "spacecraft-a"}
    })
  end
end
