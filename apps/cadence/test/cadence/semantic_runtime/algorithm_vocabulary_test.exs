defmodule Cadence.SemanticRuntime.AlgorithmVocabularyTest do
  @moduledoc """
  #451 T4a: an algorithm plan's settings decode through closed maps of the runtime's vocabulary,
  which the catalog compiler writes since #1114 (`time_basis: :receipt_time`,
  `quality_policy: :worst_input`). An unmapped value once reached evaluation and an algorithm with
  `maximum_age_ms` raised in the staleness check, tripping the partition; any value outside the
  maps, an old catalog name included, is now refused at decode with the setting named.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Declaration, Defaults, Expression}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{AlgorithmPlan, State, Update}

  test "the settings the catalog compiles by default decode into the runtime's vocabulary" do
    %{"algorithm" => %Declaration{definition: definition}} =
      Defaults.apply(%{
        "algorithm" =>
          Declaration.new(%{kind: :algorithm, qualified_name: "/algorithms/sum", definition: %{}})
      })

    plan =
      definition
      |> Map.merge(%{algorithm_id: "algorithm:sum", input_parameter_ids: [], outputs: []})
      |> AlgorithmPlan.new()

    assert %AlgorithmPlan{time_basis: :receipt_time, quality_policy: :worst_input} = plan
    assert plan.missing_input == :skip
  end

  test "the runtime's names decode, as atoms or as text" do
    assert %AlgorithmPlan{time_basis: :receipt_time} = plan(%{time_basis: "receipt_time"})
    assert %AlgorithmPlan{time_basis: :generation_time} = plan(%{time_basis: :generation_time})

    assert %AlgorithmPlan{quality_policy: :worst_input} =
             plan(%{"quality_policy" => "worst_input"})

    assert %AlgorithmPlan{missing_input: :bad_quality} = plan(%{missing_input: "bad_quality"})
  end

  test "any other value, an old catalog name included, is refused at decode, naming the setting" do
    assert_raise ArgumentError, ~r/time_basis :receipt /, fn -> plan(%{time_basis: :receipt}) end

    assert_raise ArgumentError, ~r/quality_policy :worst /, fn ->
      plan(%{quality_policy: :worst})
    end

    assert_raise ArgumentError, ~r/missing_input "drop"/, fn -> plan(%{missing_input: "drop"}) end
  end

  test "an algorithm with a maximum age skips a stale input instead of raising" do
    sum =
      plan(%{
        time_basis: :receipt_time,
        maximum_age_ms: 100,
        input_parameter_ids: ["parameter:raw", "parameter:other"],
        outputs: [
          %{
            parameter_id: "parameter:result",
            qualified_name: "/parameters/result",
            expression:
              Expression.new(%{
                node: {:+, {:parameter, "parameter:raw"}, {:parameter, "parameter:other"}},
                result_type: :number
              })
          }
        ]
      })

    runtime_plan = %{algorithms: [sum], monitoring: []}
    at = ~U[2026-11-28 12:00:00.000000Z]

    assert {:ok, _result, state} =
             SemanticRuntime.process(%State{}, [update("parameter:raw", 2, at)], runtime_plan)

    # One second later the first input is older than 100 ms: the output is skipped, not raised.
    later = DateTime.add(at, 1, :second)

    assert {:ok, result, _state} =
             SemanticRuntime.process(state, [update("parameter:other", 3, later)], runtime_plan)

    assert Enum.map(result.parameter_updates, & &1.parameter_id) == ["parameter:other"]
  end

  defp plan(attrs) do
    %{algorithm_id: "algorithm:sum", input_parameter_ids: [], outputs: []}
    |> Map.merge(attrs)
    |> AlgorithmPlan.new()
  end

  defp update(parameter_id, value, at) do
    Update.new(%{
      update_id: "#{parameter_id}:#{DateTime.to_unix(at, :microsecond)}",
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
