defmodule Cadence.FlightEventHookTest do
  @moduledoc """
  Flight events at the alarm hook: a timer-driven alarm transition records which rule opened its
  episode; without the producing generation's rule it falls back (docs/apogee/domain/flight-events.md).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Alarms.EpisodeRow
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.MissionModel.{Compiler, Layer, RuntimePlan}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.{MissionRuntimeSpec, Persistence}
  alias Cadence.SemanticObservations
  alias Cadence.SemanticRuntime.{MonitoringEvaluator, MonitoringPlan, Result, Update}

  @org "org-flight-event-hook"
  @mission "mission-flight-event-hook"
  @at ~U[2026-11-11 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "a timer-driven transition records the rule kind, id and label in its episode" do
    spec = runtime_spec([policy()])

    assert :ok =
             Persistence.persist_semantic_timer_result(
               Persistence.configured_policy(),
               spec,
               raised_result(),
               [],
               at: @at,
               timer_key: "timer-mode"
             )

    assert %EpisodeRow{context: context} = Repo.one!(EpisodeRow)

    assert %{"rule_kind" => "enumerated", "rule_id" => "rule:" <> _, "rule_label" => "default#0"} =
             context
  end

  test "a prepared result without the generation's rules (re-projection fallback) records none" do
    spec = runtime_spec([])

    prepared = %{
      raw_evidence:
        RawEvidence.new(%{
          evidence_id: "evidence-flight-event-fallback",
          mission_id: @mission,
          receipt_time: @at,
          raw: <<0>>
        }),
      semantic_result: raised_result(),
      observation_context: MissionRuntimeSpec.observation_context(spec)
    }

    assert :ok = SemanticObservations.persist_many([prepared])
    assert %EpisodeRow{context: context} = Repo.one!(EpisodeRow)
    refute Map.has_key?(context, "rule_kind")
  end

  defp raised_result do
    update =
      Update.new(%{
        update_id: "update:mode:1",
        parameter_id: "parameter:mode",
        qualified_name: "/ADCS/MODE",
        value: "SAFE",
        raw_value: 3,
        quality: :good,
        generation_time: @at,
        receipt_time: @at,
        producer_kind: :algorithm,
        producer_id: "algorithm:mode",
        metadata: %{spacecraft_id: "spacecraft-flight-event"}
      })

    {monitoring, _state} =
      MonitoringEvaluator.evaluate(MonitoringPlan.new(policy()), update, %{}, %{})

    %Result{
      parameter_updates: [update],
      monitoring_results: [monitoring],
      alarm_transitions: [monitoring]
    }
  end

  defp policy,
    do: %{
      "policy_id" => "policy:mode",
      "parameter_id" => "parameter:mode",
      "default_rules" => [
        %{"kind" => "enumerated", "values" => ["SAFE"], "severity" => "critical"}
      ]
    }

  defp runtime_spec(policies) do
    layer =
      Layer.new(%{
        organization_id: @org,
        mission_id: @mission,
        name: "flight event model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compilation} = Compiler.compile([layer])

    binding_set =
      BindingSet.new(%{
        organization_id: @org,
        mission_id: @mission,
        binding_set_id: "flight-event-binding",
        version: 1
      })

    {:ok, spec} =
      MissionRuntimeSpec.new(%{
        activation_id: "flight-event-activation",
        organization_id: @org,
        mission_id: @mission,
        generation: 1,
        binding_set_id: binding_set.binding_set_id,
        binding_set_version: binding_set.version,
        binding_set_content_sha256: MissionRuntimeSpec.content_sha256(binding_set),
        binding_set: binding_set,
        mission_model_revision_id: compilation.revision.revision_id,
        mission_model_content_sha256: compilation.revision.content_sha256,
        runtime_plans: compilation.plans,
        activated_at: ~U[2026-11-11 11:00:00Z]
      })

    %RuntimePlan{} = compiled = Map.fetch!(compilation.plans, :monitoring)
    monitoring = %{compiled | status: :ready, plan: %{"policies" => policies}}

    %{spec | runtime_plans: Map.put(spec.runtime_plans, :monitoring, monitoring)}
  end
end
