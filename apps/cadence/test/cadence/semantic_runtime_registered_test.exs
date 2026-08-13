defmodule Cadence.SemanticRuntimeRegisteredTest do
  use ExUnit.Case, async: true

  alias Cadence.SemanticRuntime.{AlgorithmPlan, RegisteredRegistry, State, Update}

  test "executes only an allowlisted registered implementation" do
    implementation =
      RegisteredRegistry.bind(
        %{kind: :registered, key: "test.triple", version: "1"},
        %{{"test.triple", "1"} => Cadence.Test.RegisteredSemanticAlgorithm}
      )

    algorithm =
      AlgorithmPlan.new(%{
        algorithm_id: "algorithm:registered",
        input_parameter_ids: ["parameter:raw"],
        implementation: implementation,
        outputs: [
          %{
            parameter_id: "parameter:registered",
            qualified_name: "/parameters/registered",
            expression: %{node: {:literal, nil}, result_type: :number}
          }
        ]
      })

    at = ~U[2026-08-11 12:00:00Z]

    update =
      Update.new(%{
        update_id: "raw:1",
        parameter_id: "parameter:raw",
        qualified_name: "/parameters/raw",
        value: 4,
        raw_value: 4,
        quality: :good,
        receipt_time: at,
        generation_time: at,
        producer_kind: :container,
        producer_id: "container:hk"
      })

    assert {:ok, result, state} =
             Cadence.SemanticRuntime.process(%State{}, [update], %{
               algorithms: [algorithm],
               monitoring: []
             })

    assert List.last(result.parameter_updates).value == 12

    assert state.algorithm_state[{{"__mission__", "__mission__"}, "algorithm:registered"}] ==
             %{count: 1}
  end

  test "fails closed when source names an implementation that is not allowlisted" do
    implementation =
      RegisteredRegistry.bind(
        %{
          kind: :registered,
          key: "not.allowed",
          version: "1",
          module: Cadence.Test.RegisteredSemanticAlgorithm
        },
        %{}
      )

    refute Map.has_key?(implementation, :module)
    assert implementation.authorization_error == :registered_implementation_not_allowed
  end
end
