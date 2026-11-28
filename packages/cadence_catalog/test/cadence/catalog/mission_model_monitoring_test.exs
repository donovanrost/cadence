Code.require_file("../../support/mission_model_mount_fixtures.exs", __DIR__)

defmodule Cadence.Catalog.MissionModelMonitoringTest do
  @moduledoc """
  ADR-020 P3 (#451): the monitoring plan's entries carry a fixed `rule_id`, a content
  `rule_digest`, their `origin` and their scope, through the real compiler, over an import (the
  catalog) and an authored layer (the mission's edits).
  """
  use ExUnit.Case, async: true

  import Cadence.Catalog.MissionModelMountFixtures

  alias Cadence.Catalog.MissionModel.{Compiler, Declaration, Layer}

  @temperature "/parameters/HK/temperature_c"
  @mode "/parameters/HK/mode"

  defp policy(path, parameter, max, extra \\ %{}) do
    Declaration.new(
      Map.merge(
        %{
          kind: :monitoring_policy,
          qualified_name: path,
          references: [%{expected_kind: :parameter, source_ref: parameter, role: :parameter}],
          definition: %{
            "default_rules" => [%{"kind" => "range", "max" => max, "severity" => "warning"}]
          }
        },
        extra
      )
    )
  end

  # The YAML bus import with one catalog policy on temperature.
  defp catalog do
    bus = yaml_layer()

    Layer.new(%{
      organization_id: bus.organization_id,
      mission_id: bus.mission_id,
      name: "bus",
      declarations: bus.declarations ++ [policy("/monitoring/temperature", @temperature, 40)]
    })
  end

  defp authored(declarations) do
    Layer.new(%{
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      layer_kind: :authored,
      name: "mission limits",
      declarations: declarations
    })
  end

  defp entries(layers) do
    assert {:ok, result} = Compiler.compile(layers)
    assert result.plans.monitoring.status == :ready, inspect(result.plans.monitoring.diagnostics)
    result.plans.monitoring.plan["policies"]
  end

  defp replace(declaration, max) do
    Declaration.new(%{
      kind: :monitoring_policy,
      qualified_name: declaration.qualified_name,
      operation: :replace,
      expected_fingerprint: Declaration.fingerprint(declaration),
      references: [%{expected_kind: :parameter, source_ref: @temperature, role: :parameter}],
      definition: %{
        "default_rules" => [%{"kind" => "range", "max" => max, "severity" => "warning"}]
      }
    })
  end

  defp catalog_policy(layer),
    do: Enum.find(layer.declarations, &(&1.qualified_name == "/monitoring/temperature"))

  test "a catalog policy is one mission-scope entry with its identity and digest" do
    assert [entry] = entries([catalog()])

    assert entry["origin"] == "catalog"
    assert entry["scope"] == "mission"
    assert entry["spacecraft_id"] == nil
    assert entry["rule_id"] == "policy:" <> entry["policy_id"]
    assert entry["declaration_id"] == entry["policy_id"]
    assert is_binary(entry["parameter_id"])
    assert "monitoring_rule:v1:" <> _ = entry["rule_digest"]
    refute Map.has_key?(entry, "spacecraft_ids")
  end

  test "a mission replace keeps the rule_id, moves the digest and says mission_layer" do
    layer = catalog()
    [before] = entries([layer])
    [edited] = entries([layer, authored([replace(catalog_policy(layer), 35)])])

    assert edited["rule_id"] == before["rule_id"]
    assert edited["rule_digest"] != before["rule_digest"]
    assert edited["origin"] == "mission_layer"
  end

  test "the digest covers what is evaluated, not where it came from" do
    layer = catalog()
    [before] = entries([layer])
    # The same thresholds, now written by the mission: no counter reset is owed.
    [same] = entries([layer, authored([replace(catalog_policy(layer), 40)])])

    assert same["origin"] == "mission_layer"
    assert same["rule_digest"] == before["rule_digest"]
  end

  test "a per-craft override takes the overridden rule_id, one entry per craft" do
    layer = catalog()

    override =
      policy("/monitoring/temperature_sc", @temperature, 30, %{
        references: [
          %{expected_kind: :parameter, source_ref: @temperature, role: :parameter},
          %{
            expected_kind: :monitoring_policy,
            source_ref: "/monitoring/temperature",
            role: :overrides
          }
        ],
        definition: %{
          "spacecraft_ids" => ["sc-2", "sc-1", "sc-2"],
          "default_rules" => [%{"kind" => "range", "max" => 30, "severity" => "warning"}]
        }
      })

    policies = entries([layer, authored([override])])
    [mission] = Enum.filter(policies, &(&1["scope"] == "mission"))
    crafts = Enum.filter(policies, &(&1["scope"] == "spacecraft"))

    assert Enum.map(crafts, & &1["spacecraft_id"]) == ["sc-1", "sc-2"]
    assert Enum.all?(crafts, &(&1["rule_id"] == mission["rule_id"]))
    # State, latest alarm state and episodes key on policy_id: the craft's continue.
    assert Enum.all?(crafts, &(&1["policy_id"] == mission["policy_id"]))
    assert Enum.all?(crafts, &(&1["origin"] == "mission_layer"))
    assert Enum.all?(crafts, &(&1["declaration_id"] != mission["declaration_id"]))
    assert Enum.all?(crafts, &(&1["rule_digest"] != mission["rule_digest"]))
  end

  test "a new spacecraft-scoped mission policy has its own rule_id" do
    scoped =
      policy("/monitoring/mode_sc", @mode, 3, %{
        definition: %{
          "spacecraft_ids" => ["sc-3"],
          "default_rules" => [%{"kind" => "range", "max" => 3, "severity" => "watch"}]
        }
      })

    policies = entries([catalog(), authored([scoped])])
    [entry] = Enum.filter(policies, &(&1["spacecraft_id"] == "sc-3"))

    assert entry["rule_id"] == "policy:" <> scoped.semantic_id
    assert entry["scope"] == "spacecraft"
    assert entry["origin"] == "mission_layer"
  end

  describe "an override is refused (a NO-GO) when" do
    test "it lists no spacecraft" do
      assert_blocked("MM_MONITORING_OVERRIDE_SCOPE_REQUIRED", @temperature, [])
    end

    test "it is on another parameter than the policy it overrides" do
      assert_blocked("MM_MONITORING_OVERRIDE_PARAMETER", @mode, ["sc-1"])
    end
  end

  test "an override naming no policy is a dangling reference" do
    override =
      policy("/monitoring/ghost", @temperature, 30, %{
        references: [
          %{expected_kind: :parameter, source_ref: @temperature, role: :parameter},
          %{expected_kind: :monitoring_policy, source_ref: "/monitoring/none", role: :overrides}
        ],
        definition: %{"spacecraft_ids" => ["sc-1"]}
      })

    assert {:ok, result} = Compiler.compile([catalog(), authored([override])])
    assert result.plans.monitoring.status == :blocked
    assert "MM_REFERENCE_DANGLING" in Enum.map(result.revision.diagnostics, & &1.code)
  end

  defp assert_blocked(code, parameter, spacecraft_ids) do
    override =
      policy("/monitoring/bad_override", parameter, 30, %{
        references: [
          %{expected_kind: :parameter, source_ref: parameter, role: :parameter},
          %{
            expected_kind: :monitoring_policy,
            source_ref: "/monitoring/temperature",
            role: :overrides
          }
        ],
        definition: %{"spacecraft_ids" => spacecraft_ids}
      })

    assert {:ok, result} = Compiler.compile([catalog(), authored([override])])
    assert result.plans.monitoring.status == :blocked
    assert code in Enum.map(result.plans.monitoring.diagnostics, & &1.code)
  end
end
