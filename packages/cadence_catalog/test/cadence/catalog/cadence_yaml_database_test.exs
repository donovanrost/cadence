defmodule Cadence.Catalog.CadenceYamlDatabaseTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.MissionModel.Compiler
  alias Cadence.Catalog.Source

  @database """
  version: "1.0.0"
  packets:
    - name: HK
      apid: 42
      items:
        - name: temperature_c
          bit_offset: 0
          bit_size: 32
          data_type: float
        - name: mode
          bit_offset: 32
          bit_size: 8
          data_type: uint
          conversion:
            type: state_table
            states:
              0: SAFE
              1: NOMINAL
  commands:
    - name: SET_MODE
      apid: 77
      opcode: 3
      parameters:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_length: 8
      effects:
        - target: HK.mode
          operation: set
          argument: mode
  """

  test "imports and compiles a combined database without Cadence persistence" do
    source =
      Source.new(%{
        artifact_id: "simulator-database",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :combined,
        artifact_name: "simulator.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: @database
      })

    assert :ok = CadenceYamlDatabase.validate(source)

    assert {:ok, import_result} =
             CadenceYamlDatabase.import(source, %{import_run_id: "simulator-import"})

    assert import_result.imported_definition_count == 2
    assert [layer] = import_result.bundle.declaration_layers

    assert Enum.any?(layer.declarations, &(&1.kind == :container and &1.name == "HK"))
    assert Enum.any?(layer.declarations, &(&1.kind == :monitoring_policy)) == false

    assert {:ok, compilation} = Compiler.compile([layer])
    assert compilation.revision.diagnostics == []

    assert [packet_definition] = compilation.plans.telemetry.plan["packet_definitions"]
    assert packet_definition["packet_name"] == "HK"
    assert Enum.map(packet_definition["fields"], & &1["name"]) == ["temperature_c", "mode"]

    assert [runtime_definition] = compilation.plans.command.plan["runtime_definitions"]
    assert runtime_definition["name"] == "SET_MODE"
    assert runtime_definition["apid"] == 77
    assert runtime_definition["mission_model_revision_id"] == compilation.revision.revision_id

    assert [state_effect] = runtime_definition["state_effects"]
    assert String.starts_with?(state_effect["target_ref"], "semantic:parameter:")
    assert state_effect["operation"] == "set"

    assert state_effect["argument_id"] ==
             runtime_definition["argument_specs"] |> hd() |> Map.fetch!("argument_id")
  end

  test "rejects command APIDs outside the Space Packet field" do
    source =
      Source.new(%{
        artifact_id: "invalid-command-apid",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        catalog_family: :command,
        artifact_name: "invalid.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        commands:
          - name: INVALID
            apid: 2048
            opcode: 1
        """
      })

    assert CadenceYamlDatabase.validate(source) ==
             {:error,
              {:validation_error, "Command 'INVALID' APID must be between 0 and 2047, got 2048"}}
  end
end
