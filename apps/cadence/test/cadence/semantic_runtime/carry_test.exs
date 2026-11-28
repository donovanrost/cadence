defmodule Cadence.SemanticRuntime.CarryTest do
  @moduledoc """
  What a partition's state keeps across a runtime basis change (#443): exactly the entries whose
  identity is in the new plan with an unchanged definition.
  """
  use ExUnit.Case, async: true

  alias Cadence.SemanticRuntime.{AlgorithmPlan, Carry, MonitoringPlan, State}

  @scope {"mission", "craft-a"}
  @other_scope {"mission", "craft-b"}

  describe "fingerprints/2" do
    test "are the same for the same plans and move with a definition" do
      assert Carry.fingerprints(%{}, plan()) == Carry.fingerprints(%{}, plan())

      changed = plan(policy: policy("p1", minimum_violations: 3))
      before = Carry.fingerprints(%{}, plan())
      later = Carry.fingerprints(%{}, changed)

      refute before.monitoring["p1"] == later.monitoring["p1"]
      assert before.monitoring["p2"] == later.monitoring["p2"]
      assert before.algorithms == later.algorithms
    end

    test "an algorithm's registered implementation is part of its definition" do
      swapped = plan(algorithm: algorithm("a1", %{kind: :registered, artifact_sha256: "new"}))
      original = plan(algorithm: algorithm("a1", %{kind: :registered, artifact_sha256: "old"}))

      refute Carry.fingerprints(%{}, original).algorithms["a1"] ==
               Carry.fingerprints(%{}, swapped).algorithms["a1"]
    end

    test "a parameter is its telemetry type and the algorithm output that derives it" do
      kelvin = telemetry([field("temp", "float", "K")])
      celsius = telemetry([field("temp", "float", "C")])
      integer = telemetry([field("temp", "int32", "K")])

      assert Carry.fingerprints(kelvin, plan()).parameters["temp"] ==
               Carry.fingerprints(telemetry([field("temp", "float", "K")]), plan()).parameters[
                 "temp"
               ]

      refute Carry.fingerprints(kelvin, plan()).parameters["temp"] ==
               Carry.fingerprints(celsius, plan()).parameters["temp"]

      refute Carry.fingerprints(kelvin, plan()).parameters["temp"] ==
               Carry.fingerprints(integer, plan()).parameters["temp"]

      # The output of a1 is derived: its definition is the parameter's.
      derived = Carry.fingerprints(%{}, plan()).parameters
      assert Map.has_key?(derived, "out-a1")

      refute Carry.fingerprints(
               %{},
               plan(algorithm: algorithm("a1", %{kind: :expression}, "pressure"))
             ).parameters[
               "out-a1"
             ] == derived["out-a1"]
    end
  end

  describe "carry/2" do
    test "keeps every entry of an unchanged plan and reports nothing dropped" do
      fingerprints = Carry.fingerprints(telemetry([field("temp", "float", "K")]), plan())
      state = evolved(fingerprints)

      assert {^state, %{kept: kept, dropped: 0}} = Carry.carry(state, fingerprints)
      assert kept == 7
    end

    test "starts fresh only for what changed" do
      runtime_plans = telemetry([field("temp", "float", "K")])
      state = evolved(Carry.fingerprints(runtime_plans, plan()))

      next = Carry.fingerprints(runtime_plans, plan(policy: policy("p1", minimum_violations: 3)))
      assert {carried, %{kept: 5, dropped: 2}} = Carry.carry(state, next)

      # p1 changed in both scopes; p2, the algorithm, its timers, memory and the parameters stay.
      refute Map.has_key?(carried.monitoring_state, {@scope, "p1"})
      refute Map.has_key?(carried.monitoring_state, {@other_scope, "p1"})
      assert Map.has_key?(carried.monitoring_state, {@scope, "p2"})
      assert Map.has_key?(carried.algorithm_state, {@scope, "a1"})
      assert Map.has_key?(carried.timer_cursors, "semantic:a1:0")
      assert Map.has_key?(carried.latest, {@scope, "temp"})
      assert carried.fingerprints == next
    end

    test "a changed implementation resets that algorithm's memory and its timers" do
      runtime_plans = telemetry([field("temp", "float", "K")])
      old = plan(algorithm: algorithm("a1", %{kind: :registered, artifact_sha256: "old"}))
      new = plan(algorithm: algorithm("a1", %{kind: :registered, artifact_sha256: "new"}))
      state = evolved(Carry.fingerprints(runtime_plans, old))

      assert {carried, _report} = Carry.carry(state, Carry.fingerprints(runtime_plans, new))
      assert carried.algorithm_state == %{}
      assert carried.timer_cursors == %{}
      assert Map.has_key?(carried.monitoring_state, {@scope, "p1"})
    end

    test "a parameter whose type changed starts without its latest value" do
      state = evolved(Carry.fingerprints(telemetry([field("temp", "float", "K")]), plan()))

      assert {carried, _report} =
               Carry.carry(
                 state,
                 Carry.fingerprints(telemetry([field("temp", "int32", "K")]), plan())
               )

      refute Map.has_key?(carried.latest, {@scope, "temp"})
      assert Map.has_key?(carried.monitoring_state, {@scope, "p1"})
    end

    test "an identity that left the plan is dropped; a new one starts empty" do
      runtime_plans = telemetry([field("temp", "float", "K")])
      state = evolved(Carry.fingerprints(runtime_plans, plan()))

      renamed = %{plan() | monitoring: [policy("p1-renamed"), policy("p2")]}
      assert {carried, _report} = Carry.carry(state, Carry.fingerprints(runtime_plans, renamed))

      refute Map.has_key?(carried.monitoring_state, {@scope, "p1"})
      refute Map.has_key?(carried.monitoring_state, {@scope, "p1-renamed"})
      assert Map.has_key?(carried.monitoring_state, {@scope, "p2"})
    end

    test "state without fingerprints (a fresh partition) carries nothing and is stamped" do
      fingerprints = Carry.fingerprints(%{}, plan())

      assert {%State{fingerprints: ^fingerprints} = carried, %{kept: 0, dropped: 0}} =
               Carry.carry(%State{}, fingerprints)

      assert carried.monitoring_state == %{}
    end
  end

  # State evolved under `fingerprints`: both policies in two scopes, the algorithm's memory and
  # its timer, and the temperature's latest value.
  defp evolved(fingerprints) do
    %State{
      latest: %{{@scope, "temp"} => :update},
      algorithm_state: %{{@scope, "a1"} => %{previous: 1}},
      monitoring_state: %{
        {@scope, "p1"} => %{effective_state: :warning},
        {@other_scope, "p1"} => %{effective_state: :normal},
        {@scope, "p2"} => %{effective_state: :normal},
        {@other_scope, "p2"} => %{effective_state: :normal}
      },
      timer_cursors: %{"semantic:a1:0" => ~U[2026-08-12 12:00:00Z]},
      fingerprints: fingerprints
    }
  end

  defp plan(opts \\ []) do
    %{
      algorithms: [Keyword.get(opts, :algorithm, algorithm("a1", %{kind: :expression}))],
      monitoring: [Keyword.get(opts, :policy, policy("p1")), policy("p2")]
    }
  end

  defp algorithm(id, implementation, source \\ "temp") do
    AlgorithmPlan.new(%{
      algorithm_id: id,
      input_parameter_ids: ["temp"],
      outputs: [
        %{
          parameter_id: "out-" <> id,
          qualified_name: "/out/" <> id,
          expression: %{node: {:parameter, source}, result_type: :number}
        }
      ],
      implementation: implementation
    })
  end

  defp policy(id, opts \\ []),
    do: MonitoringPlan.new(Map.merge(%{policy_id: id, parameter_id: "temp"}, Map.new(opts)))

  defp telemetry(fields),
    do: %{
      telemetry: %{
        status: :ready,
        plan: %{"packet_definitions" => [%{"fields" => fields}]}
      }
    }

  defp field(parameter_id, data_type, unit),
    do: %{
      "parameter_id" => parameter_id,
      "data_type" => data_type,
      "engineering_unit" => unit,
      "size_bits" => 32,
      "byte_order" => "big"
    }
end
