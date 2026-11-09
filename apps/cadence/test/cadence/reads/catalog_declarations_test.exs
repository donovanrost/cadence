defmodule Cadence.Reads.CatalogDeclarationsTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.MissionModel.Declaration
  alias Cadence.Reads.CatalogDeclarations

  defp decl(kind, path, definition, refs \\ []) do
    Declaration.new(%{
      semantic_id: path,
      kind: kind,
      qualified_name: path,
      definition: definition,
      references:
        Enum.map(refs, fn {role, id} ->
          %{expected_kind: kind, source_ref: id, role: role, resolved_id: id}
        end)
    })
  end

  defp index(declarations), do: Map.new(declarations, &{&1.semantic_id, &1})

  describe "parameter_unit/2" do
    test "follows the parameter's type to its unit (the XTCE shape)" do
      decls =
        index([
          decl(:unit, "/sc/units/V", %{symbol: "V"}),
          decl(:parameter_type, "/sc/types/Volts", %{base_type: :float}, unit: "/sc/units/V"),
          decl(:parameter, "/sc/parameters/VBAT", %{}, type: "/sc/types/Volts")
        ])

      assert CatalogDeclarations.parameter_unit(decls, "/sc/parameters/VBAT") == "V"
    end

    test "prefers the parameter's own unit and handles string-keyed definitions" do
      decls =
        index([
          decl(:unit, "/sc/units/mA", %{"symbol" => "mA"}),
          decl(:unit, "/sc/units/A", %{symbol: "A"}),
          decl(:parameter_type, "/sc/types/Amps", %{}, unit: "/sc/units/A"),
          decl(:parameter, "/sc/parameters/I", %{}, type: "/sc/types/Amps", unit: "/sc/units/mA")
        ])

      assert CatalogDeclarations.parameter_unit(decls, "/sc/parameters/I") == "mA"
    end

    test "is nil for unknown parameters and types without a unit" do
      decls =
        index([
          decl(:parameter_type, "/sc/types/Count", %{}),
          decl(:parameter, "/sc/parameters/N", %{}, type: "/sc/types/Count")
        ])

      assert CatalogDeclarations.parameter_unit(decls, "/sc/parameters/N") == nil
      assert CatalogDeclarations.parameter_unit(decls, "/sc/parameters/missing") == nil
      assert CatalogDeclarations.parameter_unit(decls, nil) == nil
    end
  end

  describe "argument_facts/2" do
    test "reads the valid range and display unit from the argument's type" do
      decls =
        index([
          decl(:command_argument_type, "/sc/command_types/Pct", %{
            valid_range: %{minimum: 0, maximum: 100},
            display_unit: "%"
          }),
          decl(:command_argument, "/sc/arguments/level", %{}, type: "/sc/command_types/Pct")
        ])

      assert CatalogDeclarations.argument_facts(decls, "/sc/arguments/level") ==
               %{valid_range: %{minimum: 0, maximum: 100}, unit: "%"}
    end

    test "a half-open range keeps nil bounds; no range or unknown argument gives nils" do
      decls =
        index([
          decl(:command_argument_type, "/sc/command_types/Pos", %{
            "valid_range" => %{"minimum" => 1}
          }),
          decl(:command_argument, "/sc/arguments/n", %{}, type: "/sc/command_types/Pos")
        ])

      assert CatalogDeclarations.argument_facts(decls, "/sc/arguments/n").valid_range ==
               %{minimum: 1, maximum: nil}

      yaml =
        index([
          decl(:command_argument_type, "/sc/command_types/Y", %{valid_range: %{min: -5, max: 5}}),
          decl(:command_argument, "/sc/arguments/y", %{}, type: "/sc/command_types/Y")
        ])

      assert CatalogDeclarations.argument_facts(yaml, "/sc/arguments/y").valid_range ==
               %{minimum: -5, maximum: 5}

      assert CatalogDeclarations.argument_facts(decls, "/sc/arguments/none") ==
               %{valid_range: nil, unit: nil}
    end
  end
end
