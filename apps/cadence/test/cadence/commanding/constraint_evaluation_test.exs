defmodule Cadence.Commanding.ConstraintEvaluationTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.ConstraintPlan
  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Commanding.ConstraintEvaluation
  alias Cadence.Telemetry.Sample

  test "evaluates compound constraints across latest semantic parameter values" do
    temperature_id = "semantic:parameter:temperature"
    mode_id = "semantic:parameter:mode"

    criteria =
      MatchCriteria.new(%{
        criteria_type: :compound,
        operator: :and,
        conditions: [
          %{
            criteria_type: :comparison,
            subject_ref: temperature_id,
            comparison: :less,
            value: 90
          },
          %{
            criteria_type: :comparison,
            subject_ref: mode_id,
            comparison: :equal,
            value: "SAFE"
          }
        ]
      })

    plan =
      ConstraintPlan.new(%{
        command_id: "set-mode",
        constraint_id: "safe-to-command",
        name: "Safe to command",
        constraint_type: :precondition,
        criteria: criteria,
        blocking: true
      })

    values =
      ConstraintEvaluation.latest_values([
        sample("temperature", temperature_id, 85, ~U[2026-08-12 12:00:01Z]),
        sample("mode", mode_id, "SAFE", ~U[2026-08-12 12:00:01Z])
      ])

    assert :ok = ConstraintEvaluation.validate([plan], values)

    unsafe_values = Map.put(values, temperature_id, 95)

    assert {:error, {:command_constraint_not_satisfied, "safe-to-command"}} =
             ConstraintEvaluation.validate([plan], unsafe_values)
  end

  test "uses the first sample as the latest value for each subject" do
    parameter_id = "semantic:parameter:temperature"

    values =
      ConstraintEvaluation.latest_values([
        sample("temperature", parameter_id, 20, ~U[2026-08-12 12:00:02Z]),
        sample("temperature", parameter_id, 10, ~U[2026-08-12 12:00:01Z])
      ])

    assert values[parameter_id] == 20
  end

  defp sample(point_name, semantic_id, value, at) do
    %Sample{
      sample_id: point_name <> DateTime.to_iso8601(at),
      mission_id: "mission-alpha",
      spacecraft_id: "spacecraft-alpha",
      point_id: point_name,
      point_name: point_name,
      semantic_id: semantic_id,
      qualified_name: "/parameters/" <> point_name,
      packet_definition_id: "packet-hk",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      engineering_value: value,
      quality_state: :good,
      generation_time: at,
      receipt_time: at,
      provenance: %{}
    }
  end
end
