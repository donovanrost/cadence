defmodule Cadence.Catalog.CadenceYamlDatabaseTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler, as: CommandCompiler
  alias Cadence.Catalog.Command.Decoder
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source
  alias Cadence.Catalog.Telemetry.Compiler, as: TelemetryCompiler

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
    assert import_result.bundle.telemetry_snapshot.snapshot_name == "simulator.yaml"
    assert import_result.bundle.command_snapshot.snapshot_name == "simulator.yaml"

    assert %{packet_definitions: [packet_definition], diagnostics: []} =
             TelemetryCompiler.compile(import_result.bundle.telemetry_snapshot)

    assert packet_definition.packet_name == "HK"
    assert Enum.map(packet_definition.fields, & &1.name) == ["temperature_c", "mode"]

    assert %{runtime_definitions: [runtime_definition], diagnostics: []} =
             CommandCompiler.compile(import_result.bundle.command_snapshot)

    assert runtime_definition.name == "SET_MODE"
    assert runtime_definition.apid == 77
    assert [state_effect] = runtime_definition.state_effects
    assert state_effect.target_ref == "HK.mode"
    assert state_effect.operation == :set
    assert state_effect.argument_id == hd(runtime_definition.argument_specs).argument_id

    assert {:ok, decoded} = Decoder.decode([runtime_definition], <<3, 1>>)

    assert decoded.runtime_definition.command_id == runtime_definition.command_id
    assert decoded.arguments == %{"mode" => 1}
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
