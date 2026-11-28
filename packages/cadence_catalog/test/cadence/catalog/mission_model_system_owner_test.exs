Code.require_file("../../support/mission_model_mount_fixtures.exs", __DIR__)

defmodule Cadence.Catalog.MissionModelSystemOwnerTest do
  @moduledoc """
  ADR-020 P5 (#1078), slice A: every lowered definition says which `SpaceSystem` owns it, and its
  qualified runtime name, so a spacecraft bound to some systems of a revision can select their
  definitions.
  """
  use ExUnit.Case, async: true

  import Cadence.Catalog.MissionModelMountFixtures

  alias Cadence.Catalog.MissionModel.{
    Compiler,
    Declaration,
    Layer,
    MonitoringLowering,
    SystemOwner
  }

  defp compile do
    bus = yaml_layer()
    payload = xtce_layer()

    policy =
      Declaration.new(%{
        kind: :monitoring_policy,
        qualified_name: "/bus/monitoring/temperature",
        references: [
          %{
            expected_kind: :parameter,
            source_ref: "/bus/parameters/HK/temperature_c",
            role: :parameter
          }
        ],
        definition: %{
          "default_rules" => [%{"kind" => "range", "max" => 40, "severity" => "warning"}]
        }
      })

    authored =
      Layer.new(%{
        organization_id: bus.organization_id,
        mission_id: bus.mission_id,
        layer_kind: :authored,
        name: "limits",
        declarations: [policy]
      })

    assert {:ok, result} =
             Compiler.compile([bus, payload, authored],
               mounts: %{bus.layer_id => "/bus", payload.layer_id => "/payload"}
             )

    result
  end

  defp system_id(result, path),
    do:
      Enum.find_value(result.revision.space_systems, fn {id, s} ->
        s.qualified_name == path && id
      end)

  test "containers and commands say which system owns them and what they are called there" do
    result = compile()

    assert [hk] =
             Enum.filter(
               result.plans.telemetry.plan["packet_definitions"],
               &(&1["packet_name"] == "HK")
             )

    assert hk["space_system_id"] == system_id(result, "/bus")
    assert hk["space_system_path"] == "/bus"
    assert hk["runtime_name"] == "/bus/HK"

    assert [set_mode] =
             Enum.filter(
               result.plans.command.plan["runtime_definitions"],
               &(&1["name"] == "SET_MODE")
             )

    assert set_mode["space_system_id"] == system_id(result, "/bus")
    assert set_mode["runtime_name"] == "/bus/SET_MODE"
  end

  test "algorithms and monitoring entries carry their owner too" do
    result = compile()

    assert [algorithm] = result.plans.algorithm.plan["algorithms"]
    assert algorithm["space_system_id"] == system_id(result, "/payload/Vehicle")
    assert algorithm["runtime_name"] == "/payload/Vehicle/DoubleTemperature"

    assert [entry] = result.plans.monitoring.plan["policies"]
    assert entry["space_system_id"] == system_id(result, "/bus")
    assert entry["space_system_path"] == "/bus"
    assert entry["runtime_name"] == "/bus/temperature"
  end

  test "where a policy lives is not part of its rule digest" do
    result = compile()
    assert [entry] = result.plans.monitoring.plan["policies"]

    moved =
      Map.merge(entry, %{"space_system_id" => "other", "runtime_name" => "/other/temperature"})

    assert MonitoringLowering.rule_digest(moved) ==
             entry["rule_digest"]
  end

  test "one import at the root is owned by the root, named from it" do
    assert {:ok, result} = Compiler.compile([yaml_layer()])

    assert [hk] = result.plans.telemetry.plan["packet_definitions"]
    assert hk["space_system_path"] == "/"
    assert hk["runtime_name"] == "/HK"
  end

  test "a declaration with no declared system above it carries nothing but its name" do
    declaration = Declaration.new(%{kind: :container, qualified_name: "/x/containers/HK"})

    assert SystemOwner.fields(declaration, %{}) == %{
             "space_system_id" => nil,
             "space_system_path" => nil,
             "runtime_name" => "HK"
           }
  end
end
