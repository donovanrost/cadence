defmodule Cadence.Management.Commanding.WireAuthoringTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Management.Commanding.RequestAuthoring

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

    for {name, command} <- model.commands_by_name do
      assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => command})
      assert catalog["selected_command"]["supported"], "#{name} must support wire encoding"
    end

    command = model.commands_by_name["SET_MODE"]
    assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => command})
    assert [%{"name" => "mode", "choices" => choices}] = catalog["selected_command"]["arguments"]
    assert length(choices) == 7

    assert {:ok, held} =
             RequestAuthoring.preview(c.scope, c.mission, %{
               "expected_basis" => catalog["basis"]["token"],
               "source_endpoint_ref" => c.target.source_endpoint_id,
               "command_id" => command,
               "argument_values_json" => ~s({"mode":3}),
               "priority" => 3,
               "not_before" => nil,
               "expires_at" => nil
             })

    assert held.request.resolved_argument_values == %{"mode" => 3}
  end

  test "an imported but unsupported float width is unavailable for authoring", c do
    c = activate(c, "float", 16)
    assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => c.command})
    refute catalog["selected_command"]["supported"]

    assert {:error, :unsupported_command_wire_definition} =
             RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, 1.0))

    refute Repo.exists?(CommandRequestRow)
  end

  test "native float32 requests reject overflow while preserving representable values", c do
    c = activate(c, "float", 32)
    assert {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{"command" => c.command})
    assert catalog["selected_command"]["supported"]
    assert {:error, _} = RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, 1.0e100))
    refute Repo.exists?(CommandRequestRow)
    assert {:ok, held} = RequestAuthoring.preview(c.scope, c.mission, input(c, catalog, 1.5))
    assert held.request.resolved_argument_values == %{"value" => 1.5}
  end

  defp input(c, catalog, value) do
    %{
      "expected_basis" => catalog["basis"]["token"],
      "source_endpoint_ref" => c.target.source_endpoint_id,
      "command_id" => c.command,
      "argument_values_json" => Jason.encode!(%{"value" => value}),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }
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
