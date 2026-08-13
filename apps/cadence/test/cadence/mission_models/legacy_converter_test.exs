defmodule Cadence.MissionModels.LegacyConverterTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer}
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.MissionModels.LegacyConverter
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}

  test "converts legacy derived telemetry and limits into executable authored declarations" do
    raw_parameter =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: "/parameters/HK.temperature",
        aliases: ["HK.temperature"],
        definition: %{point_id: "HK.temperature"}
      })

    base_layer =
      Layer.new(%{
        organization_id: "org-legacy-converter",
        mission_id: "mission-legacy-converter",
        name: "base",
        declarations: [
          %{kind: :space_system, qualified_name: "/"},
          raw_parameter
        ]
      })

    assert {:ok, base} = Compiler.compile([base_layer])

    derived =
      Definition.new(%{
        derived_definition_id: "derived-double-temperature",
        mission_id: base.revision.mission_id,
        point_id: "CALC.double_temperature",
        point_name: "CALC.double_temperature",
        expression: "HK.temperature * 2"
      })

    limits =
      LimitDefinition.new(%{
        limit_definition_id: "limit-double-temperature",
        mission_id: base.revision.mission_id,
        point_id: derived.point_id,
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    assert {:ok, authored_layer, []} =
             LegacyConverter.convert(base.revision, [derived], [limits],
               actor: %{"id" => "operator-1"}
             )

    assert authored_layer.layer_kind == :authored
    assert {:ok, compilation} = Compiler.compile([base_layer, authored_layer])
    assert Enum.all?(compilation.plans, fn {_target, plan} -> plan.status == :ready end)

    plan = PlanDecoder.decode(compilation.plans)
    at = ~U[2026-08-11 12:00:00Z]

    update =
      Update.new(%{
        update_id: "raw:1",
        parameter_id: raw_parameter.semantic_id,
        qualified_name: raw_parameter.qualified_name,
        value: 6,
        raw_value: 6,
        quality: :good,
        receipt_time: at,
        generation_time: at,
        producer_kind: :container,
        producer_id: "container:hk"
      })

    assert {:ok, result, _state} = Cadence.SemanticRuntime.process(%State{}, [update], plan)
    assert List.last(result.parameter_updates).value == 12
    assert [%{effective_state: :warning}] = result.monitoring_results
  end

  test "returns a stable error diagnostic for an unresolved legacy point" do
    layer =
      Layer.new(%{
        organization_id: "org-legacy-converter",
        mission_id: "mission-legacy-converter",
        name: "base",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    assert {:ok, base} = Compiler.compile([layer])

    limit =
      LimitDefinition.new(%{
        limit_definition_id: "missing-limit",
        mission_id: base.revision.mission_id,
        point_id: "missing.point",
        thresholds: %{"red_high" => 10}
      })

    assert {:ok, _authored_layer, [diagnostic]} =
             LegacyConverter.convert(base.revision, [], [limit])

    assert diagnostic.code == "MM_LEGACY_LIMIT_PARAMETER_UNRESOLVED"
    assert diagnostic.severity == :error
  end
end
