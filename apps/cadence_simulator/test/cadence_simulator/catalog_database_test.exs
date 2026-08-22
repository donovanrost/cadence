defmodule CadenceSimulator.CatalogDatabaseTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.CatalogDatabase

  @database """
  packets:
    - name: HK
      apid: 42
      items:
        - name: counter
          bit_offset: 0
          bit_size: 16
          data_type: uint
  commands:
    - name: RESET_COUNTER
      opcode: 7
      effects:
        - target: HK.counter
          operation: set
          value: 0
  """

  test "loads and compiles a combined database through the shared catalog app" do
    assert {:ok, database} =
             CatalogDatabase.load_yaml(
               @database,
               %{
                 artifact_id: "simulator-db",
                 mission_id: "mission-alpha",
                 artifact_name: "mission-alpha.yaml"
               },
               import_run_id: "simulator-import"
             )

    assert database.source.mission_id == "mission-alpha"
    assert database.import_result.imported_definition_count == 2

    assert [packet_definition] = database.packet_definitions
    assert packet_definition.packet_name == "HK"
    assert packet_definition.version == 1
    assert Enum.map(packet_definition.fields, & &1.name) == ["counter"]

    assert [runtime_definition] = database.command_definitions
    assert runtime_definition.name == "RESET_COUNTER"

    assert [%{target_ref: target_ref, operation: :set, value: 0}] =
             runtime_definition.state_effects

    assert String.starts_with?(target_ref, "semantic:parameter:")

    assert {:ok, decoded} = CatalogDatabase.decode_command(database, <<7, 0, 0>>)
    assert decoded.runtime_definition.name == "RESET_COUNTER"
    assert decoded.arguments == %{}
    assert CatalogDatabase.diagnostics(database) == []
  end
end
