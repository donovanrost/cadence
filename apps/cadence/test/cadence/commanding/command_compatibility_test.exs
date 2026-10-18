defmodule Cadence.Catalog.Command.CompatibilityTest do
  use Cadence.DataCase, async: false
  alias Cadence.Catalog.Command.Compatibility, as: CommandCompatibility
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source
  alias Cadence.MissionModels
  alias Cadence.Runtime.MissionModelPlanDecoder

  test "shared preparation tolerates distinct model identities but rejects different wire encodings" do
    persist_mission_scope("org-compatibility", "mission-compatibility")
    first = catalog("first", 1)
    compatible = catalog("compatible", 1)
    incompatible = catalog("incompatible", 2)
    [definition] = first.runtime_definitions
    assert {:ok, fingerprint} = CommandCompatibility.fingerprint(first, definition.command_id)

    assert {:ok, ^fingerprint} =
             CommandCompatibility.fingerprint(compatible, definition.command_id)

    assert {:ok, changed} = CommandCompatibility.fingerprint(incompatible, definition.command_id)
    refute changed == fingerprint

    # Identical wire encodings do not imply identical allowed argument values.
    assert {:ok, allowed} =
             CommandCompatibility.fingerprint(first, definition.command_id, %{
               "mode" => [%{label: "1", value: 1}]
             })

    assert {:ok, changed_choices} =
             CommandCompatibility.fingerprint(first, definition.command_id, %{
               "mode" => [%{label: "1", value: 1}, %{label: "2", value: 2}]
             })

    refute allowed == changed_choices

    assert {:error, :command_not_in_spacecraft_catalog} =
             CommandCompatibility.fingerprint(first, "missing-command")
  end

  defp catalog(id, opcode) do
    source =
      Source.new(%{
        artifact_id: id,
        organization_id: "org-compatibility",
        mission_id: "mission-compatibility",
        catalog_family: :combined,
        artifact_name: "commands.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        commands:
          - name: SET_MODE
            opcode: #{opcode}
            parameters:
              - name: mode
                data_type: uint
                required: true
                bit_offset: 0
                bit_length: 8
        """
      })

    {:ok, imported} = CadenceYamlDatabase.import(source, %{import_run_id: id})
    {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)
    {:ok, catalog} = MissionModelPlanDecoder.command_authoring_catalog(compilation.plans)
    catalog
  end
end
