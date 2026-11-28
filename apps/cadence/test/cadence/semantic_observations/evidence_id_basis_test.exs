defmodule Cadence.SemanticObservations.EvidenceIdBasisTest do
  @moduledoc """
  #950 (items 1 and 3 of #167, part of #166): the monitoring evaluation id, the alarm transition id
  and the derived `parameter_update` id are `ContentBasis` digests of NAMED SCALARS, so a replay
  recomputes the same id whatever the result and update structs have grown since.

  - GOLDEN: fixed inputs pinned to their exact bytes and digests. NEVER just re-pin one: find
    what moved it. A change of what an id covers is a basis VERSION bump and a reseed plan (no
    legacy basis exists in dev, DECISIONS #108 as amended by #112).
  - CANARY: every field of the structs the ids read is listed with its role; a new field fails
    here until it is put in the basis (version bump) or excluded on purpose.
  - REPLAY: the same evidence persisted again, or recomputed with a different outcome payload,
    finds the same ids and writes no second evaluation or transition.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Platform.ContentBasis
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.{AlarmTransitionRow, MonitoringEvaluationRow}
  alias Cadence.SemanticRuntime

  alias Cadence.SemanticRuntime.{
    AlgorithmPlan,
    IdBasis,
    MonitoringResult,
    RegisteredRegistry,
    State,
    Update
  }

  alias Cadence.TestSupport.ContentBasisCanary

  @org "org-evidence-ids"
  @mission "mission-evidence-ids"
  @at ~U[2026-11-28 12:00:00.000000Z]

  @evaluation_attrs %{
    organization_id: "org-1",
    mission_id: "mission-1",
    spacecraft_id: "sc-1",
    parameter_id: "parameter:temp",
    policy_id: "policy:temp",
    update_id: "update-1"
  }

  @golden_evaluation_bytes ~s(monitoring_evaluation:v1:{"mission_id":"mission-1","organization_id":"org-1","parameter_id":"parameter:temp","policy_id":"policy:temp","spacecraft_id":"sc-1","update_id":"update-1"})
  @golden_evaluation_id "monitoring_evaluation:v1:4bd67547056d8868a9da3c493ed36e17ab1979529e2bf1051b3b6d849dd963f2"
  @golden_transition_bytes ~s(alarm_transition:v1:{"evaluation_id":"monitoring_evaluation:v1:4bd67547056d8868a9da3c493ed36e17ab1979529e2bf1051b3b6d849dd963f2","from_state":"normal","to_state":"critical"})
  @golden_transition_id "alarm_transition:v1:d206fadf365e77d06032c311a0722ad9253d630b75a7cd96716c4f1b6c580b25"
  @golden_update_bytes ~s(parameter_update:v1:{"algorithm_id":"algorithm:out","parameter_id":"parameter:out","trigger_id":"parameter:in:1795867200","value":13})
  @golden_update_id "parameter_update:v1:e7dae5dcadd4924d9745b4542fcf58868d35906086ba92beef3b06977ba2e2a9"

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  describe "golden ids" do
    test "the monitoring evaluation id" do
      assert ContentBasis.encoded(
               "monitoring_evaluation",
               1,
               basis(MonitoringEvaluationRow, @evaluation_attrs)
             ) ==
               @golden_evaluation_bytes

      assert MonitoringEvaluationRow.evaluation_id(@evaluation_attrs) == @golden_evaluation_id

      # What is not identity does not move it: the outcome, the plan, the times, the payload.
      noisy =
        Map.merge(@evaluation_attrs, %{
          effective_state: "critical",
          violation_count: 9,
          runtime_plan_id: "plan-2",
          mission_model_revision_id: "rev-2",
          receipt_time: @at,
          evaluation_document: %{"anything" => 1}
        })

      assert MonitoringEvaluationRow.evaluation_id(noisy) == @golden_evaluation_id
    end

    test "the alarm transition id" do
      attrs = %{
        evaluation_id: @golden_evaluation_id,
        from_state: "normal",
        to_state: "critical"
      }

      assert ContentBasis.encoded("alarm_transition", 1, basis(AlarmTransitionRow, attrs)) ==
               @golden_transition_bytes

      assert AlarmTransitionRow.transition_id(attrs) == @golden_transition_id

      noisy = Map.merge(attrs, %{receipt_time: @at, transition_document: %{"x" => 1}})
      assert AlarmTransitionRow.transition_id(noisy) == @golden_transition_id

      refute AlarmTransitionRow.transition_id(%{attrs | to_state: "warning"}) ==
               @golden_transition_id
    end

    test "the derived parameter_update id, over every supported value type" do
      assert ContentBasis.encoded("parameter_update", 1,
               algorithm_id: "algorithm:out",
               parameter_id: "parameter:out",
               trigger_id: "parameter:in:1795867200",
               value: 13
             ) == @golden_update_bytes

      assert derived_id(13) == @golden_update_id

      # A value is part of the identity, and its type is: 13 and 13.0 are different values.
      refute derived_id(13.0) == @golden_update_id
      refute derived_id(14) == @golden_update_id
    end
  end

  describe "canonical values" do
    test "the supported types have a canonical form" do
      assert {:ok, 1} = IdBasis.value(1)
      assert {:ok, 1.5} = IdBasis.value(1.5)
      assert {:ok, true} = IdBasis.value(true)
      assert {:ok, nil} = IdBasis.value(nil)
      assert {:ok, :ok} = IdBasis.value(:ok)
      assert {:ok, "text"} = IdBasis.value("text")
      assert {:ok, %{:"$cadence_bytes" => <<255>>}} = IdBasis.value(<<255>>)
      assert {:ok, [1, [2]]} = IdBasis.value([1, [2]])
      assert {:ok, %{a: 1, b: [2]}} = IdBasis.value(%{a: 1, b: [2]})

      assert {:ok, %{"$cadence_datetime" => "2026-11-28T12:00:00.000000Z"}} =
               IdBasis.value(~U[2026-11-28 12:00:00Z])

      assert {:ok, %{"$cadence_decimal" => "1.50"}} = IdBasis.value(Decimal.new("1.50"))
    end

    test "times are UTC with six digits, whatever the precision or zone they arrive in" do
      assert IdBasis.time(~U[2026-11-28 12:00:00Z]) == "2026-11-28T12:00:00.000000Z"
      assert IdBasis.time(~U[2026-11-28 12:00:00.000000Z]) == "2026-11-28T12:00:00.000000Z"
      assert IdBasis.time(nil) == nil
    end

    test "a struct, a tuple or a pid has no canonical form, and says so" do
      assert {:error, {:unsupported_value, "Cadence.SemanticRuntime.Update"}} =
               IdBasis.value(%Update{
                 update_id: "u",
                 parameter_id: "p",
                 qualified_name: "q",
                 value: 1,
                 quality: :good,
                 receipt_time: @at,
                 producer_kind: :algorithm,
                 producer_id: "a"
               })

      assert {:error, {:unsupported_value, "tuple"}} = IdBasis.value({:a, 1})
      assert {:error, {:unsupported_value, "pid"}} = IdBasis.value([self()])
      assert {:error, {:unsupported_value, "map key"}} = IdBasis.value(%{{:a} => 1})
    end

    test "an algorithm output with no canonical form is refused with its parameter named" do
      assert {:error,
              {"algorithm:out",
               {:unsupported_derived_value, "parameter:out", {:unsupported_value, "tuple"}}}} =
               run_registered(Cadence.Test.TupleOutputAlgorithm)
    end
  end

  describe "struct canary" do
    test "the fields of MonitoringResult and Update each have a role in the evaluation id" do
      # `MonitoringEvaluationRow.basis_fields/0` names parameter_id, policy_id and update_id from the
      # result, the rest of the basis is the row's own scalars (organization, mission, spacecraft).
      ContentBasisCanary.assert_struct_fields!(MonitoringResult, "monitoring_evaluation", 1,
        included: [:parameter_id, :policy_id, :update_id],
        excluded: [
          :conformance_count,
          :effective_state,
          :evaluated_state,
          :matched_context,
          :metadata,
          :previous_state,
          :transition,
          :violation_count
        ]
      )

      # From the update only its spacecraft (`metadata.spacecraft_id`) is identity.
      ContentBasisCanary.assert_struct_fields!(Update, "monitoring_evaluation", 1,
        included: [:metadata],
        excluded: [
          :generation_time,
          :parameter_id,
          :producer_id,
          :producer_kind,
          :quality,
          :qualified_name,
          :raw_value,
          :receipt_time,
          :source_update_ids,
          :update_id,
          :value
        ]
      )
    end

    test "the named fields of each basis are pinned" do
      assert MonitoringEvaluationRow.basis_fields() ==
               [
                 :organization_id,
                 :mission_id,
                 :spacecraft_id,
                 :parameter_id,
                 :policy_id,
                 :update_id
               ]

      assert AlarmTransitionRow.basis_fields() == [:evaluation_id, :from_state, :to_state]
    end
  end

  describe "replay" do
    defp counts do
      {Repo.aggregate(MonitoringEvaluationRow, :count),
       Repo.aggregate(AlarmTransitionRow, :count)}
    end

    defp batch(opts \\ []) do
      prepared = transition(@org, @mission, "sc-1", "P1", {:normal, :critical}, @at, "replay-1")

      update_in(prepared.semantic_result.monitoring_results, fn [result] ->
        [struct(result, Keyword.get(opts, :result, []))]
      end)
    end

    test "persisting the same evidence again writes no second evaluation or transition" do
      assert :ok = SemanticObservations.persist_many([batch()])
      assert {1, 1} = counts()

      assert :ok = SemanticObservations.persist_many([batch()])
      assert {1, 1} = counts()
    end

    test "recomputed with a different outcome payload, it finds the same ids (no fork)" do
      assert :ok = SemanticObservations.persist_many([batch()])
      [first] = Repo.all(MonitoringEvaluationRow)
      [first_transition] = Repo.all(AlarmTransitionRow)

      # The same update and policy, evaluated again with other counts, metadata and match: what a
      # newer struct or a different recovery would produce.
      assert :ok =
               SemanticObservations.persist_many([
                 batch(
                   result: [
                     violation_count: 7,
                     metadata: %{rule_changed: %{from: "a", to: "b"}},
                     matched_context: "ctx"
                   ]
                 )
               ])

      assert {1, 1} = counts()
      assert [%{evaluation_id: id}] = Repo.all(MonitoringEvaluationRow)
      assert id == first.evaluation_id
      assert [%{transition_id: tid}] = Repo.all(AlarmTransitionRow)
      assert tid == first_transition.transition_id
    end
  end

  # -- helpers --------------------------------------------------------------------------------

  defp basis(module, attrs), do: Enum.map(module.basis_fields(), &{&1, Map.get(attrs, &1)})

  defp derived_id(value) do
    plan = %{algorithms: [passthrough(value)], monitoring: []}

    {:ok, result, _state} =
      SemanticRuntime.process(%State{}, [input_update("parameter:in", 1, @at)], plan)

    %Update{update_id: id} =
      Enum.find(result.parameter_updates, &(&1.parameter_id == "parameter:out"))

    id
  end

  defp passthrough(value) do
    AlgorithmPlan.new(%{
      algorithm_id: "algorithm:out",
      input_parameter_ids: ["parameter:in"],
      outputs: [
        %{
          parameter_id: "parameter:out",
          qualified_name: "/parameters/out",
          expression: %{node: {:literal, value}, result_type: :number}
        }
      ]
    })
  end

  defp run_registered(module) do
    implementation =
      RegisteredRegistry.bind(
        %{kind: :registered, key: "test.tuple", version: "1"},
        %{{"test.tuple", "1"} => module}
      )

    algorithm =
      AlgorithmPlan.new(%{
        algorithm_id: "algorithm:out",
        input_parameter_ids: ["parameter:in"],
        implementation: implementation,
        outputs: [
          %{
            parameter_id: "parameter:out",
            qualified_name: "/parameters/out",
            expression: %{node: {:literal, nil}, result_type: :number}
          }
        ]
      })

    plan = %{algorithms: [algorithm], monitoring: []}

    case SemanticRuntime.process(%State{}, [input_update("parameter:in", 1, @at)], plan) do
      {:error, reason} -> {:error, reason}
      {:ok, _result, _state} -> :ok
    end
  end

  defp input_update(parameter_id, value, at) do
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
