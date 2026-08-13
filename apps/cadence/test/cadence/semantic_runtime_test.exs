defmodule Cadence.SemanticRuntimeTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Expression

  alias Cadence.SemanticRuntime.{
    AlgorithmPlan,
    MonitoringPlan,
    State,
    Update
  }

  test "cascades ordered derived updates and applies monitoring persistence" do
    plan = %{
      algorithms: [
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:double",
          input_parameter_ids: ["parameter:raw"],
          outputs: [
            %{
              parameter_id: "parameter:double",
              qualified_name: "/parameters/double",
              expression: expression({:*, {:parameter, "parameter:raw"}, {:literal, 2}}, :number)
            }
          ]
        }),
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:offset",
          input_parameter_ids: ["parameter:double"],
          outputs: [
            %{
              parameter_id: "parameter:result",
              qualified_name: "/parameters/result",
              expression:
                expression({:+, {:parameter, "parameter:double"}, {:literal, 1}}, :number)
            }
          ]
        })
      ],
      monitoring: [
        MonitoringPlan.new(%{
          policy_id: "monitor:result",
          parameter_id: "parameter:result",
          minimum_violations: 2,
          minimum_conformance: 1,
          default_rules: [
            %{kind: :comparison, operator: :>, value: 10, severity: :critical}
          ]
        })
      ]
    }

    at = ~U[2026-08-11 12:00:00.000000Z]
    first = update("raw:1", 6, at)

    assert {:ok, first_result, state} = Cadence.SemanticRuntime.process(%State{}, [first], plan)

    assert Enum.map(first_result.parameter_updates, &{&1.parameter_id, &1.value}) == [
             {"parameter:raw", 6},
             {"parameter:double", 12},
             {"parameter:result", 13}
           ]

    assert [%{evaluated_state: :critical, effective_state: :normal}] =
             first_result.monitoring_results

    assert first_result.alarm_transitions == []

    second = update("raw:2", 7, DateTime.add(at, 1, :second))
    assert {:ok, second_result, _state} = Cadence.SemanticRuntime.process(state, [second], plan)

    assert [%{effective_state: :critical, transition: %{from: :normal, to: :critical}}] =
             second_result.alarm_transitions
  end

  test "stateful delta, rate, and bounded windows are explicit and deterministic" do
    expression =
      expression(
        {:+, {:stateful, :delta, "delta", {:parameter, "parameter:raw"}, %{}},
         {:stateful, :rolling_avg, "window", {:parameter, "parameter:raw"}, %{size: 2}}},
        :number
      )

    plan = %{
      algorithms: [
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:stateful",
          input_parameter_ids: ["parameter:raw"],
          outputs: [
            %{
              parameter_id: "parameter:stateful",
              qualified_name: "/parameters/stateful",
              expression: expression
            }
          ]
        })
      ],
      monitoring: []
    }

    at = ~U[2026-08-11 12:00:00.000000Z]

    assert {:ok, first, state} =
             Cadence.SemanticRuntime.process(%State{}, [update("raw:1", 2, at)], plan)

    assert List.last(first.parameter_updates).value == 2.0

    assert {:ok, second, _state} =
             Cadence.SemanticRuntime.process(
               state,
               [update("raw:2", 6, DateTime.add(at, 1, :second))],
               plan
             )

    assert List.last(second.parameter_updates).value == 8.0
  end

  test "missing and stale inputs skip output under the default policy" do
    plan = %{
      algorithms: [
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:aligned",
          input_parameter_ids: ["parameter:raw", "parameter:other"],
          maximum_age_ms: 100,
          outputs: [
            %{
              parameter_id: "parameter:result",
              qualified_name: "/parameters/result",
              expression:
                expression(
                  {:+, {:parameter, "parameter:raw"}, {:parameter, "parameter:other"}},
                  :number
                )
            }
          ]
        })
      ],
      monitoring: []
    }

    at = ~U[2026-08-11 12:00:00.000000Z]

    assert {:ok, result, state} =
             Cadence.SemanticRuntime.process(%State{}, [update("raw:1", 2, at)], plan)

    assert Enum.map(result.parameter_updates, & &1.parameter_id) == ["parameter:raw"]

    %Update{} = other_update = update("other:1", 3, DateTime.add(at, 1, :second))
    other = %Update{other_update | parameter_id: "parameter:other"}

    assert {:ok, result, _state} = Cadence.SemanticRuntime.process(state, [other], plan)
    assert Enum.map(result.parameter_updates, & &1.parameter_id) == ["parameter:other"]
  end

  test "isolates latest values and state by spacecraft scope" do
    plan = %{
      algorithms: [
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:delta",
          input_parameter_ids: ["parameter:raw"],
          outputs: [
            %{
              parameter_id: "parameter:delta",
              qualified_name: "/parameters/delta",
              expression:
                expression(
                  {:stateful, :delta, "delta", {:parameter, "parameter:raw"}, %{}},
                  :number
                )
            }
          ]
        })
      ],
      monitoring: []
    }

    at = ~U[2026-08-11 12:00:00.000000Z]
    alpha = scoped_update("alpha:1", 10, at, "alpha")
    beta = scoped_update("beta:1", 100, at, "beta")

    assert {:ok, first, state} = Cadence.SemanticRuntime.process(%State{}, [alpha, beta], plan)

    assert Enum.map(first.parameter_updates, &{&1.metadata.spacecraft_id, &1.value}) == [
             {"alpha", 10},
             {"alpha", 0},
             {"beta", 100},
             {"beta", 0}
           ]

    assert {:ok, second, _state} =
             Cadence.SemanticRuntime.process(
               state,
               [scoped_update("alpha:2", 13, DateTime.add(at, 1), "alpha")],
               plan
             )

    assert List.last(second.parameter_updates).value == 3
  end

  test "periodic triggers execute zero-input algorithms at the deterministic due time" do
    plan = %{
      algorithms: [
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:heartbeat",
          input_parameter_ids: [],
          triggers: [%{kind: :periodic, interval_ms: 1_000}],
          outputs: [
            %{
              parameter_id: "parameter:heartbeat",
              qualified_name: "/parameters/heartbeat",
              expression: expression({:literal, 1}, :number)
            }
          ]
        })
      ],
      monitoring: []
    }

    at = ~U[2026-08-11 12:00:01.000000Z]
    scope = {"mission", "spacecraft"}

    assert {:ok, result, state} =
             Cadence.SemanticRuntime.timer(
               %State{},
               scope,
               "algorithm:heartbeat",
               at,
               plan
             )

    assert [update] = result.parameter_updates
    assert update.value == 1
    assert update.generation_time == at
    assert update.receipt_time == at
    assert update.metadata.mission_id == "mission"
    assert update.metadata.spacecraft_id == "spacecraft"
    assert state.sequence == 1
  end

  defp expression(node, type), do: Expression.new(%{node: node, result_type: type})

  defp update(id, value, at) do
    Update.new(%{
      update_id: id,
      parameter_id: "parameter:raw",
      qualified_name: "/parameters/raw",
      value: value,
      raw_value: value,
      quality: :good,
      receipt_time: at,
      generation_time: at,
      producer_kind: :container,
      producer_id: "container:hk"
    })
  end

  defp scoped_update(id, value, at, spacecraft_id) do
    %Update{} = parameter_update = update(id, value, at)

    %Update{
      parameter_update
      | metadata: %{mission_id: "mission", spacecraft_id: spacecraft_id}
    }
  end
end
