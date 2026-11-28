defmodule Cadence.MissionModels.MonitoringPlanTest do
  @moduledoc """
  ADR-020 P3 (#451), the 12-01 interface for telemetry's T1/T2: `MissionModels.fetch_runtime_plans/3`
  serves a compiled monitoring plan whose entries decode into `SemanticRuntime.MonitoringPlan`
  with `rule_id`, `rule_digest`, `origin`, `declaration_id`, `scope` and `spacecraft_id`. The
  revision is compiled through the real compiler from an import and an authored layer (the
  mission's edits); the monitoring lane that will write authored layers comes next.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.MissionModel.{Declaration, Layer}
  alias Cadence.MissionModels
  alias Cadence.SemanticRuntime.{MonitoringPlan, PlanDecoder}

  @org "org-monitoring-plan"
  @temperature "/parameters/temperature"

  setup do
    mission = "mission-monitoring-plan-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission}
  end

  test "the stored plan's entries carry identity, digest, origin and scope", %{mission: mission} do
    imported = imported(mission)
    catalog = Enum.find(imported.declarations, &(&1.kind == :monitoring_policy))

    authored =
      Layer.new(%{
        organization_id: @org,
        mission_id: mission,
        layer_kind: :authored,
        name: "mission limits",
        declarations: [
          %{
            kind: :monitoring_policy,
            qualified_name: catalog.qualified_name,
            operation: :replace,
            expected_fingerprint: Declaration.fingerprint(catalog),
            references: [parameter_ref()],
            definition: rules(35)
          },
          %{
            kind: :monitoring_policy,
            qualified_name: "/monitoring/temperature_sc_1",
            references: [
              parameter_ref(),
              %{
                expected_kind: :monitoring_policy,
                source_ref: catalog.qualified_name,
                role: :overrides
              }
            ],
            definition: Map.put(rules(30), "spacecraft_ids", ["sc-1"])
          }
        ]
      })

    {:ok, result} = MissionModels.compile_layers([imported, authored])
    revision_id = result.revision.revision_id

    assert {:ok, %{monitoring: stored}} =
             MissionModels.fetch_runtime_plans(@org, mission, revision_id)

    assert stored.target_contract_version == "2"
    assert stored.status == :ready

    %{monitoring: plans} = PlanDecoder.decode(%{monitoring: stored})
    [mission_plan] = Enum.filter(plans, &(&1.scope == :mission))
    [craft_plan] = Enum.filter(plans, &(&1.scope == :spacecraft))

    assert %MonitoringPlan{origin: :mission_layer, spacecraft_id: nil} = mission_plan
    assert mission_plan.rule_id == "policy:" <> catalog.semantic_id
    assert "monitoring_rule:v1:" <> _ = mission_plan.rule_digest

    assert %MonitoringPlan{origin: :mission_layer, spacecraft_id: "sc-1"} = craft_plan
    assert craft_plan.rule_id == mission_plan.rule_id
    assert craft_plan.rule_digest != mission_plan.rule_digest
    assert craft_plan.parameter_id == mission_plan.parameter_id
    refute craft_plan.declaration_id == mission_plan.declaration_id
  end

  test "an import alone is catalog-origin, mission-scope", %{mission: mission} do
    {:ok, result} = MissionModels.compile_layers([imported(mission)])

    {:ok, %{monitoring: stored}} =
      MissionModels.fetch_runtime_plans(@org, mission, result.revision.revision_id)

    %{monitoring: [plan]} = PlanDecoder.decode(%{monitoring: stored})
    assert %MonitoringPlan{origin: :catalog, scope: :mission, spacecraft_id: nil} = plan
  end

  defp imported(mission) do
    Layer.new(%{
      organization_id: @org,
      mission_id: mission,
      name: "bus",
      declarations: [
        %{kind: :space_system, qualified_name: "/"},
        %{kind: :parameter, qualified_name: @temperature},
        %{
          kind: :monitoring_policy,
          qualified_name: "/monitoring/temperature",
          references: [parameter_ref()],
          definition: rules(40)
        }
      ]
    })
  end

  defp parameter_ref, do: %{expected_kind: :parameter, source_ref: @temperature, role: :parameter}

  defp rules(max),
    do: %{"default_rules" => [%{"kind" => "range", "max" => max, "severity" => "warning"}]}
end
