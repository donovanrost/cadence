defmodule Cadence.Management.Commanding.WireAuthoringTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures

  alias Cadence.{
    CommandAuthoringFixtures,
    CommandReviewFixtures,
    Ids,
    MissionModelFixtures,
    MissionModels
  }

  setup do
    c = CommandReviewFixtures.scope!()
    Map.put(c, :target, CommandAuthoringFixtures.target!(c.org, c.mission))
  end

  test "the full demo database supports command arguments also used by state effects", c do
    path =
      Path.expand(
        "../../../../../../dev/catalogs/demo_spacecraft.yaml",
        __DIR__
      )

    source =
      Source.new(%{
        artifact_id: Ids.new("demo_commands"),
        organization_id: c.org,
        mission_id: c.mission,
        catalog_family: :combined,
        artifact_name: "demo_spacecraft.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: File.read!(path)
      })

    assert {:ok, imported} =
             CadenceYamlDatabase.import(source, %{import_run_id: Ids.new("demo_import")})

    assert {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)

    model =
      MissionModelFixtures.activate_imported_model!(c.org, c.mission, %{
        "mission_model" => %{"revision_id" => compilation.revision.revision_id}
      })

    assert map_size(model.commands_by_name) == 27

    assert {:ok, held} =
             Fixtures.validate(Map.put(c, :model, model), "SET_MODE", %{"mode" => 3})

    assert held.request.resolved_argument_values == %{"mode" => 3}
  end

  test "an imported but unsupported float width is refused", c do
    c = activate(c, "float", 16)

    assert {:error, :unsupported_command_wire_definition} =
             Fixtures.validate(c, c.command, %{"value" => 1.0})

    refute Repo.exists?(CommandRequestRow)
  end

  test "native float32 requests reject overflow while preserving representable values", c do
    c = activate(c, "float", 32)
    assert {:error, _} = Fixtures.validate(c, c.command, %{"value" => 1.0e100})
    refute Repo.exists?(CommandRequestRow)
    assert {:ok, held} = Fixtures.validate(c, c.command, %{"value" => 1.5})
    assert held.request.resolved_argument_values == %{"value" => 1.5}
  end

  defp activate(c, type, bits) do
    source =
      Source.new(%{
        artifact_id: Ids.new("wire_model"),
        organization_id: c.org,
        mission_id: c.mission,
        catalog_family: :combined,
        artifact_name: "wire.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        commands:
          - name: CHECK_WIRE
            opcode: 7
            parameters:
              - name: value
                data_type: #{type}
                required: true
                bit_offset: 0
                bit_length: #{bits}
        """
      })

    {:ok, imported} = CadenceYamlDatabase.import(source, %{import_run_id: Ids.new("wire_import")})
    {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)

    model =
      MissionModelFixtures.activate_imported_model!(c.org, c.mission, %{
        "mission_model" => %{"revision_id" => compilation.revision.revision_id}
      })

    Map.merge(c, %{command: model.commands_by_name["CHECK_WIRE"], revision: model.revision_id})
  end
end
