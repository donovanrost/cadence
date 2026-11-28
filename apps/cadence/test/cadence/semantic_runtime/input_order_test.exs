defmodule Cadence.SemanticRuntime.InputOrderTest do
  @moduledoc """
  #451 T4c: a registered algorithm receives its inputs in their declared order, duplicates
  included (#454), through the context's `inputs_in_order`, beside the map by id.
  """
  use ExUnit.Case, async: true

  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{AlgorithmPlan, RegisteredRegistry, State, Update}

  @at ~U[2026-11-28 12:00:00Z]

  test "the declared order decides a positional input, and a repeated input is passed twice" do
    # declared: b, a, b. first - second = 3 - 10, plus 3 declared inputs * 1000.
    assert difference(["parameter:b", "parameter:a", "parameter:b"]) == 3 - 10 + 3_000
    # the same inputs declared the other way round give the other difference
    assert difference(["parameter:a", "parameter:b"]) == 10 - 3 + 2_000
  end

  defp difference(input_parameter_ids) do
    implementation =
      RegisteredRegistry.bind(
        %{kind: :registered, key: "test.positional", version: "1"},
        %{{"test.positional", "1"} => Cadence.Test.PositionalSemanticAlgorithm}
      )

    algorithm =
      AlgorithmPlan.new(%{
        algorithm_id: "algorithm:difference",
        input_parameter_ids: input_parameter_ids,
        implementation: implementation,
        outputs: [
          %{
            parameter_id: "parameter:difference",
            qualified_name: "/parameters/difference",
            expression: %{node: {:literal, nil}, result_type: :number}
          }
        ]
      })

    plan = %{algorithms: [algorithm], monitoring: []}

    {:ok, _result, state} =
      SemanticRuntime.process(%State{}, [update("parameter:a", 10, @at)], plan)

    {:ok, result, _state} =
      SemanticRuntime.process(state, [update("parameter:b", 3, DateTime.add(@at, 1))], plan)

    %Update{value: value} =
      Enum.find(result.parameter_updates, &(&1.parameter_id == "parameter:difference"))

    value
  end

  defp update(parameter_id, value, at) do
    Update.new(%{
      update_id: "#{parameter_id}:#{DateTime.to_unix(at)}",
      parameter_id: parameter_id,
      qualified_name: "/parameters/#{parameter_id}",
      value: value,
      raw_value: value,
      quality: :good,
      receipt_time: at,
      generation_time: at,
      producer_kind: :container,
      producer_id: "container:hk"
    })
  end
end
