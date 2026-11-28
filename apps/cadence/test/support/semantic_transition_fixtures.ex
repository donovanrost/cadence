defmodule Cadence.TestSupport.SemanticTransitionFixtures do
  @moduledoc """
  Prepared semantic results for `SemanticObservations.persist_many/1`: one monitoring transition of
  one parameter on one spacecraft, the way the partition owner hands them to the writer.
  """

  alias Cadence.Ingress.RawEvidence
  alias Cadence.SemanticRuntime.{MonitoringResult, Result, Update}

  @doc """
  `transition(org, mission, craft, parameter, {from, to}, at, id)`: `id` makes the update and the
  evidence unique.
  """
  def transition(organization_id, mission_id, craft, parameter, {from, to}, at, id) do
    update =
      Update.new(%{
        update_id: "update-#{id}",
        parameter_id: parameter,
        qualified_name: parameter,
        value: id,
        raw_value: id,
        quality: :good,
        generation_time: at,
        receipt_time: at,
        producer_kind: :container,
        producer_id: "container-fixture",
        metadata: %{spacecraft_id: craft}
      })

    %{
      raw_evidence:
        RawEvidence.new(%{
          evidence_id: "evidence-#{id}",
          mission_id: mission_id,
          receipt_time: at,
          raw: <<0>>
        }),
      observation_context: %{
        organization_id: organization_id,
        mission_id: mission_id,
        mission_model_revision_id: "model-fixture",
        runtime_plan_id: "plan-fixture"
      },
      semantic_result: %Result{
        parameter_updates: [update],
        monitoring_results: [
          %MonitoringResult{
            policy_id: "policy-#{parameter}",
            parameter_id: parameter,
            update_id: update.update_id,
            evaluated_state: to,
            effective_state: to,
            previous_state: from,
            transition: %{from: from, to: to},
            violation_count: 0,
            conformance_count: 1
          }
        ]
      }
    }
  end
end
