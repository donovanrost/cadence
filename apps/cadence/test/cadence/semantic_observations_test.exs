defmodule Cadence.SemanticObservationsTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Layer}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.AlarmTransitionRow
  alias Cadence.SemanticRuntime.{MonitoringResult, Result, Update}

  test "persists every evaluation, transition, latest state, and acknowledgement" do
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

    prepared = %{raw_evidence: evidence, semantic_result: result, runtime_spec: runtime_spec}

    assert :ok = SemanticObservations.persist_many([prepared])
    assert :ok = SemanticObservations.persist_many([prepared])

    assert [latest] = SemanticObservations.list_latest(organization_id, mission_id)
    assert latest.parameter_id == update.parameter_id
    assert latest.effective_state == "critical"

    assert %AlarmTransitionRow{} = transition = Repo.one!(AlarmTransitionRow)

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
end
