defmodule Cadence.SemanticObservationsTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Layer}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.SemanticObservations

  alias Cadence.SemanticObservations.{
    AlarmTransitionRow,
    LatestAlarmStateRow,
    MonitoringEvaluationRow
  }

  alias Cadence.SemanticRuntime.{MonitoringResult, Result, Update}

  test "preserves transition evidence, latest state, acknowledgements and late-arrival ordering" do
    organization_id = "org-semantic-observations"
    mission_id = "mission-semantic-observations"
    persist_mission_scope(organization_id, mission_id)

    layer =
      Layer.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        name: "observation model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    assert {:ok, compilation} = Compiler.compile([layer])

    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: "observation-binding",
        version: 1
      })

    assert {:ok, runtime_spec} =
             MissionRuntimeSpec.new(%{
               activation_id: "observation-activation",
               organization_id: organization_id,
               mission_id: mission_id,
               generation: 1,
               binding_set_id: binding_set.binding_set_id,
               binding_set_version: binding_set.version,
               binding_set: binding_set,
               mission_model_revision_id: compilation.revision.revision_id,
               mission_model_content_sha256: compilation.revision.content_sha256,
               runtime_plans: compilation.plans,
               activated_at: ~U[2026-08-11 12:00:00Z]
             })

    at = ~U[2026-08-11 12:00:01.000000Z]

    %Update{} =
      update =
      Update.new(%{
        update_id: "update:temperature:1",
        parameter_id: "parameter:temperature",
        qualified_name: "/parameters/temperature",
        value: 110,
        raw_value: 110,
        quality: :good,
        generation_time: at,
        receipt_time: at,
        producer_kind: :container,
        producer_id: "container:hk",
        metadata: %{spacecraft_id: "spacecraft-alpha"}
      })

    monitoring = %MonitoringResult{
      policy_id: "policy:temperature",
      parameter_id: update.parameter_id,
      update_id: update.update_id,
      evaluated_state: :critical,
      effective_state: :critical,
      previous_state: :normal,
      transition: %{from: :normal, to: :critical},
      violation_count: 1,
      conformance_count: 0
    }

    result = %Result{
      parameter_updates: [update],
      monitoring_results: [monitoring],
      alarm_transitions: [monitoring]
    }

    evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-observation-1",
        mission_id: mission_id,
        receipt_time: at,
        raw: <<0>>
      })

    prepared = %{
      raw_evidence: evidence,
      semantic_result: result,
      observation_context: MissionRuntimeSpec.observation_context(runtime_spec)
    }

    assert :ok = SemanticObservations.persist_many([prepared])
    assert :ok = SemanticObservations.persist_many([prepared])

    assert [latest] = SemanticObservations.list_latest(organization_id, mission_id)
    assert latest.parameter_id == update.parameter_id
    assert latest.effective_state == "critical"

    assert %AlarmTransitionRow{} = transition = Repo.one!(AlarmTransitionRow)
    assert evaluation = Repo.get!(MonitoringEvaluationRow, transition.evaluation_id)
    assert evaluation.update_id == update.update_id
    assert evaluation.evaluation_document == JsonDocument.wrap_value(monitoring)

    assert {:ok, acknowledgement} =
             SemanticObservations.acknowledge(
               organization_id,
               mission_id,
               transition.transition_id,
               %{"kind" => "user", "id" => "operator-1"},
               note: "reviewed",
               at: ~U[2026-08-11 12:05:00Z]
             )

    assert acknowledgement.note == "reviewed"

    late_generation_time = DateTime.add(at, -1, :second)
    late_receipt_time = DateTime.add(at, 10, :minute)

    late_update = %Update{
      update
      | update_id: "update:temperature:late",
        value: 70,
        raw_value: 70,
        generation_time: late_generation_time,
        receipt_time: late_receipt_time
    }

    late_monitoring = %MonitoringResult{
      monitoring
      | update_id: late_update.update_id,
        evaluated_state: :normal,
        effective_state: :normal,
        previous_state: :critical,
        transition: %{from: :critical, to: :normal},
        violation_count: 0,
        conformance_count: 1
    }

    late_prepared = %{
      raw_evidence:
        RawEvidence.new(%{
          evidence_id: "evidence-observation-late",
          mission_id: mission_id,
          receipt_time: late_receipt_time,
          raw: <<0>>
        }),
      semantic_result: %Result{
        parameter_updates: [late_update],
        monitoring_results: [late_monitoring],
        alarm_transitions: [late_monitoring]
      },
      runtime_spec: runtime_spec
    }

    assert :ok = SemanticObservations.persist_many([late_prepared])

    assert [latest_after_late_arrival] =
             SemanticObservations.list_latest(organization_id, mission_id)

    assert latest_after_late_arrival.effective_state == "critical"
    assert latest_after_late_arrival.transition_id == transition.transition_id
  end

  test "acknowledgement rejects a transition outside the supplied scope" do
    assert {:error, :semantic_alarm_transition_not_found} =
             SemanticObservations.acknowledge(
               "wrong-org",
               "wrong-mission",
               "missing-transition",
               %{"kind" => "user", "id" => "operator-1"}
             )
  end

  test "routine normal and unchanged alarm evaluations require no database queries" do
    prepared = Enum.map(1..1_001, &prepared_evaluation/1)
    unchanged_alarm = prepared_evaluation(1_002)

    [monitoring] = unchanged_alarm.semantic_result.monitoring_results

    unchanged_alarm =
      put_in(unchanged_alarm.semantic_result.monitoring_results, [
        %{
          monitoring
          | evaluated_state: :critical,
            effective_state: :critical,
            previous_state: :critical,
            violation_count: 12,
            conformance_count: 0
        }
      ])

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(handler, [:cadence, :repo, :query], &__MODULE__.capture_query/4, self())

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :ok = SemanticObservations.persist_many([unchanged_alarm | prepared])
    refute_received {:monitoring_query, _}
    :telemetry.detach(handler)

    assert Repo.aggregate(MonitoringEvaluationRow, :count) == 0
    assert Repo.aggregate(AlarmTransitionRow, :count) == 0
    assert Repo.aggregate(LatestAlarmStateRow, :count) == 0
  end

  test "mixed batches retain only transition evaluations, including alarm clearance" do
    persist_mission_scope("org-monitoring-batch", "mission-monitoring-batch")
    raised = prepared_evaluation(1, {:normal, :critical})
    routine = prepared_evaluation(2)
    cleared = prepared_evaluation(3, {:critical, :normal})

    prepared = %{
      raised
      | semantic_result: %Result{
          parameter_updates:
            Enum.flat_map([raised, routine, cleared], & &1.semantic_result.parameter_updates),
          monitoring_results:
            Enum.flat_map([raised, routine, cleared], & &1.semantic_result.monitoring_results)
        }
    }

    assert :ok = SemanticObservations.persist_many([prepared])
    assert :ok = SemanticObservations.persist_many([prepared])

    evaluations = Repo.all(MonitoringEvaluationRow)

    assert Enum.sort(Enum.map(evaluations, & &1.update_id)) == [
             "update-batch-1",
             "update-batch-3"
           ]

    assert Enum.all?(evaluations, & &1.transitioned)

    for transition <- Repo.all(AlarmTransitionRow) do
      evaluation = Repo.get!(MonitoringEvaluationRow, transition.evaluation_id)

      assert evaluation.evaluation_document["value"]["transition"] ==
               JsonDocument.unwrap_value(transition.transition_document)
    end

    assert Repo.aggregate(AlarmTransitionRow, :count) == 2

    assert [latest] =
             SemanticObservations.list_latest("org-monitoring-batch", "mission-monitoring-batch")

    assert latest.effective_state == "normal"
    assert Repo.get!(AlarmTransitionRow, latest.transition_id).to_state == "normal"
  end

  test "transition evidence remains complete, idempotent and atomic across insert chunks" do
    persist_mission_scope("org-monitoring-batch", "mission-monitoring-batch")
    prepared = Enum.map(1..1_001, &prepared_evaluation(&1, {:normal, :critical}))

    assert :ok = SemanticObservations.persist_many(prepared)
    assert :ok = SemanticObservations.persist_many(prepared)
    assert Repo.aggregate(MonitoringEvaluationRow, :count) == 1_001
    assert Repo.aggregate(AlarmTransitionRow, :count) == 1_001

    invalid =
      put_in(
        prepared_evaluation(1_003, {:normal, :critical}).observation_context.runtime_plan_id,
        nil
      )

    assert {:error, %Ecto.Changeset{}} =
             SemanticObservations.persist_many([
               prepared_evaluation(1_002, {:normal, :critical}),
               invalid
             ])

    assert Repo.aggregate(MonitoringEvaluationRow, :count) == 1_001
    assert Repo.aggregate(AlarmTransitionRow, :count) == 1_001
  end

  def capture_query(_event, _measurements, metadata, owner) do
    if self() == owner, do: send(owner, {:monitoring_query, metadata.query})
  end

  defp prepared_evaluation(index, transition \\ nil) do
    at = DateTime.add(~U[2026-08-11 12:00:01.000000Z], index, :second)
    {previous, effective} = transition || {:normal, :normal}

    update =
      Update.new(%{
        update_id: "update-batch-#{index}",
        parameter_id: "parameter-batch",
        qualified_name: "/parameters/batch",
        value: index,
        raw_value: index,
        quality: :good,
        generation_time: at,
        receipt_time: at,
        producer_kind: :container,
        producer_id: "container-batch",
        metadata: %{spacecraft_id: "spacecraft-batch"}
      })

    %{
      raw_evidence:
        RawEvidence.new(%{
          evidence_id: "evidence-batch-#{index}",
          mission_id: "mission-monitoring-batch",
          receipt_time: at,
          raw: <<0>>
        }),
      observation_context: %{
        organization_id: "org-monitoring-batch",
        mission_id: "mission-monitoring-batch",
        mission_model_revision_id: "model-batch",
        runtime_plan_id: "plan-batch"
      },
      semantic_result: %Result{
        parameter_updates: [update],
        monitoring_results: [
          %MonitoringResult{
            policy_id: "policy-batch",
            parameter_id: update.parameter_id,
            update_id: update.update_id,
            evaluated_state: effective,
            effective_state: effective,
            previous_state: previous,
            transition: if(transition, do: %{from: previous, to: effective}),
            violation_count: 0,
            conformance_count: 1
          }
        ]
      }
    }
  end
end
