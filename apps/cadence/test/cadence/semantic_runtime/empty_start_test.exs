defmodule Cadence.SemanticRuntime.EmptyStartTest do
  @moduledoc """
  A partition starting from an empty State (every runtime-basis change, director 11-15): seeded
  monitoring priors clear an alarm that cleared while down and don't raise one still active; a
  `missing_input: :bad_quality` algorithm no longer fails the evidence (the journal wedge).
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Expression
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{AlgorithmPlan, MonitoringPlan, Scope, State, Update}

  @at ~U[2026-11-15 12:00:00.000000Z]

  describe "seeded monitoring priors" do
    test "an alarm that cleared while down clears on the first normal sample" do
      seeded =
        SemanticRuntime.seed_monitoring(%State{}, [{Scope.mission(), "monitor:raw", :critical}])

      assert {:ok, result, _state} =
               SemanticRuntime.process(seeded, [update("raw:1", 1)], monitoring())

      assert [%{transition: %{from: :critical, to: :normal}}] = result.alarm_transitions

      # Unseeded (today's empty start): the prior is :normal, so no clear is ever emitted.
      assert {:ok, unseeded, _state} =
               SemanticRuntime.process(%State{}, [update("raw:1", 1)], monitoring())

      assert unseeded.alarm_transitions == []
    end

    test "an alarm still active raises nothing new" do
      seeded =
        SemanticRuntime.seed_monitoring(%State{}, [{Scope.mission(), "monitor:raw", :critical}])

      assert {:ok, result, _state} =
               SemanticRuntime.process(seeded, [update("raw:1", 50)], monitoring())

      assert result.alarm_transitions == []
      assert [%{effective_state: :critical}] = result.monitoring_results
    end

    test "a policy the state already knows keeps its own state" do
      known = %{
        effective_state: :normal,
        candidate_state: :normal,
        violation_count: 0,
        conformance_count: 3
      }

      key = Scope.state_key(Scope.mission(), "monitor:raw")
      state = %State{monitoring_state: %{key => known}}

      seeded =
        SemanticRuntime.seed_monitoring(state, [{Scope.mission(), "monitor:raw", :critical}])

      assert seeded.monitoring_state[key] == known
    end
  end

  describe "missing_input: :bad_quality (the wedge)" do
    test "a missing input skips the algorithm instead of failing the evidence" do
      assert {:ok, result, _state} =
               SemanticRuntime.process(%State{}, [update("raw:1", 2)], bad_quality_plan())

      assert Enum.map(result.parameter_updates, & &1.parameter_id) == ["parameter:raw"]
    end

    test "stale inputs are used, and the output is marked bad" do
      %Update{} = raw = update("other:1", 3)
      other = %Update{raw | parameter_id: "parameter:other"}
      {:ok, _result, state} = SemanticRuntime.process(%State{}, [other], bad_quality_plan())

      later = update("raw:1", 2, DateTime.add(@at, 1, :second))
      assert {:ok, result, _state} = SemanticRuntime.process(state, [later], bad_quality_plan())

      assert %Update{value: 5, quality: :bad} = List.last(result.parameter_updates)
    end
  end

  defp monitoring do
    %{
      algorithms: [],
      monitoring: [
        MonitoringPlan.new(%{
          policy_id: "monitor:raw",
          parameter_id: "parameter:raw",
          default_rules: [%{kind: :comparison, operator: :>, value: 10, severity: :critical}]
        })
      ]
    }
  end

  defp bad_quality_plan do
    %{
      algorithms: [
        AlgorithmPlan.new(%{
          algorithm_id: "algorithm:sum",
          input_parameter_ids: ["parameter:raw", "parameter:other"],
          missing_input: :bad_quality,
          maximum_age_ms: 100,
          outputs: [
            %{
              parameter_id: "parameter:sum",
              qualified_name: "/parameters/sum",
              expression:
                Expression.new(%{
                  node: {:+, {:parameter, "parameter:raw"}, {:parameter, "parameter:other"}},
                  result_type: :number
                })
            }
          ]
        })
      ],
      monitoring: []
    }
  end

  defp update(id, value, at \\ @at) do
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
end
