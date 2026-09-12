defmodule Cadence.ExactCommandAuthoringFixtures do
  @moduledoc false
  alias Cadence.{
    CommandAuthoringFixtures,
    CommandReviewFixtures,
    Ids,
    MissionModelFixtures,
    MissionModels
  }

  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source
  alias Cadence.Management.Commanding.RequestAuthoring
  @maximum 18_446_744_073_709_551_615

  def fixture! do
    c = CommandReviewFixtures.scope!()

    Map.merge(c, %{
      model: activate!(c.org, c.mission),
      target: CommandAuthoringFixtures.target!(c.org, c.mission)
    })
  end

  def input(c, command, values) do
    {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{})

    %{
      "expected_basis" => catalog["basis"]["token"],
      "source_endpoint_ref" => c.target.source_endpoint_id,
      "command_id" => c.model.commands_by_name[command],
      "argument_values_json" => Jason.encode!(values),
      "priority" => 3,
      "not_before" => nil,
      "expires_at" => nil
    }
  end

  def activate!(org, mission, extra_commands \\ "") do
    yaml = """
    commands:
      - name: SET_COUNTER
        opcode: 1
        is_hazardous: true
        hazard_description: Changes the spacecraft counter
        requires_confirmation: true
        parameters:
          - name: amount
            data_type: uint
            required: true
            bit_offset: 0
            bit_length: 8
          - name: counter
            data_type: uint
            required: false
            default_value: #{@maximum}
            bit_offset: 8
            bit_length: 64
      - name: SET_SIGNED
        opcode: 2
        parameters:
          - name: counter
            data_type: int
            required: true
            bit_offset: 0
            bit_length: 64
      - name: SET_ENUM
        opcode: 3
        parameters:
          - name: counter
            data_type: uint
            required: true
            valid_values: [#{@maximum}]
            bit_offset: 0
            bit_length: 64
    """

    source =
      Source.new(%{
        artifact_id: Ids.new("exact_model"),
        organization_id: org,
        mission_id: mission,
        catalog_family: :combined,
        artifact_name: "commands.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: yaml <> extra_commands
      })

    {:ok, imported} =
      CadenceYamlDatabase.import(source, %{import_run_id: Ids.new("exact_import")})

    {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)

    MissionModelFixtures.activate_imported_model!(org, mission, %{
      "mission_model" => %{"revision_id" => compilation.revision.revision_id}
    })
  end
end
