defmodule Cadence.Catalog.CadenceYamlDatabaseTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler, as: CommandCompiler
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
      opcode: 3
      parameters:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_length: 8
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
  end
end
