defmodule Cadence.SemanticRuntimeStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer}
  alias Cadence.Runtime.{MissionRuntimeSpec, PartitionKey}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, Scope, State, Store, Update}

  test "commits idempotently and reconstructs state from ordered durable inputs" do
    {runtime_spec, input_id} = runtime_spec()
    partition_key = PartitionKey.new(%{affinity: :source_endpoint, value: "pobc"})
    plan = PlanDecoder.decode(runtime_spec.runtime_plans)
    at = ~U[2026-08-12 12:00:00Z]

    first = update("update:1", input_id, 10, at)
    second = update("update:2", input_id, 15, DateTime.add(at, 1, :second))

    assert {:ok, first_result, first_state} =
             SemanticRuntime.process(%State{}, [first], plan)

    assert {:ok, ^first_result, ^first_state} =
             Store.commit(runtime_spec, partition_key, [first], first_result, first_state)

    assert {:ok, ^first_result, ^first_state} =
             Store.commit(runtime_spec, partition_key, [first], first_result, first_state)

    assert {:ok, second_result, second_state} =
             SemanticRuntime.process(first_state, [second], plan)

    assert {:ok, ^second_result, ^second_state} =
             Store.commit(runtime_spec, partition_key, [second], second_result, second_state)

    assert {:ok, ^second_state} = Store.recover(runtime_spec, partition_key, plan)
  end

  test "retains unprojected timer results until their observation projection is acknowledged" do
    {runtime_spec, input_id} = runtime_spec()
    partition_key = PartitionKey.new(%{affinity: :source_endpoint, value: "pobc-timer"})
    plan = PlanDecoder.decode(runtime_spec.runtime_plans)
    at = ~U[2026-08-12 12:00:00Z]
    input = update("update:timer", input_id, 10, at)

    assert {:ok, _result, state} = SemanticRuntime.process(%State{}, [input], plan)
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

    assert {:ok, ^timer_result, ^timer_state} =
             Store.commit_timer(
               runtime_spec,
               partition_key,
               Scope.new("semantic-store-mission", "spacecraft-a"),
               algorithm_id,
               timer_at,
               "periodic:" <> algorithm_id,
               timer_result,
               timer_state
             )

    assert {:ok, [pending]} = Store.pending_timer_results(runtime_spec, partition_key)
    assert pending.at == timer_at
    assert pending.result == timer_result

    assert :ok =
             Store.mark_timer_projected(
               runtime_spec,
               partition_key,
               pending.timer_key,
               timer_at
             )

    assert {:ok, []} = Store.pending_timer_results(runtime_spec, partition_key)
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
