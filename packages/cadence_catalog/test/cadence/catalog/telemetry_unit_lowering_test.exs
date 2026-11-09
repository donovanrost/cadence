defmodule Cadence.Catalog.TelemetryUnitLoweringTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.{Compiler, Layer}

  defp layer(parameter_unit?) do
    parameter_refs =
      [%{expected_kind: :parameter_type, source_ref: "/v/types/volts", role: :type}] ++
        if parameter_unit?,
          do: [%{expected_kind: :unit, source_ref: "/v/units/mV", role: :unit}],
          else: []

    Layer.new(%{
      organization_id: "org-u",
      mission_id: "mission-u",
      name: "units",
      declarations: [
        %{kind: :space_system, qualified_name: "/"},
        %{kind: :space_system, qualified_name: "/v"},
        %{kind: :unit, qualified_name: "/v/units/V", definition: %{symbol: "V"}},
        %{kind: :unit, qualified_name: "/v/units/mV", definition: %{symbol: "mV"}},
        %{
          kind: :parameter_type,
          qualified_name: "/v/types/volts",
          definition: %{base_type: :integer, encoding: %{size_bits: 16, signed: false}},
          references: [%{expected_kind: :unit, source_ref: "/v/units/V", role: :unit}]
        },
        %{kind: :parameter, qualified_name: "/v/parameters/vbat", references: parameter_refs},
        %{
          kind: :container,
          qualified_name: "/v/containers/HK",
          definition: %{
            apid: 42,
            entries: [%{parameter_ref: "/v/parameters/vbat", bit_offset: 0}]
          },
          references: [
            %{expected_kind: :parameter, source_ref: "/v/parameters/vbat", role: :entry}
          ]
        }
      ]
    })
  end

  defp lowered_unit(layer) do
    assert {:ok, %{plans: %{telemetry: plan}}} = Compiler.compile([layer])
    assert plan.status == :ready
    assert [%{"fields" => [field]}] = plan.plan["packet_definitions"]
    field["engineering_unit"]
  end

  test "a unit declared on the parameter type reaches the lowered field (the XTCE shape)" do
    assert lowered_unit(layer(false)) == "V"
  end

  test "the parameter's own unit wins over its type's" do
    assert lowered_unit(layer(true)) == "mV"
  end
end
