defmodule Cadence.CommandAuthoringFixtures do
  @moduledoc false
  alias Cadence.Catalog.Importers.CadenceYamlDatabase
  alias Cadence.Catalog.Source
  alias Cadence.{CommandReviewFixtures, Ids, MissionModelFixtures, MissionModels, SourceEndpoints}
  alias Cadence.SourceEndpoints.SourceEndpoint

  def fixture! do
    c = CommandReviewFixtures.scope!()
    model = activate!(c.org, c.mission)
    target = target!(c.org, c.mission)
    Map.merge(c, %{model: model, target: target})
  end

  def target!(org, mission, attrs \\ %{}) do
    {:ok, target} =
      SourceEndpoints.persist_source_endpoint(
        org,
        SourceEndpoint.new(
          Map.merge(
            %{
              organization_id: org,
              mission_id: mission,
              source_endpoint_id: Ids.new("authoring_target"),
              display_name: "Flight command endpoint",
              source_ref: "fixture:uplink",
              scid: 7,
              metadata: %{"private" => "target-secret"}
            },
            attrs
          )
        )
      )

    target
  end

  def activate!(org, mission, count \\ 2) do
    commands =
      for i <- 1..count do
        """
          - name: COMMAND_#{i}
            opcode: #{i}
            is_hazardous: #{i == 1}
            hazard_description: Fixture command changes spacecraft power
            requires_confirmation: #{i == 1}
            parameters:
              - name: amount
                data_type: uint
                required: true
                bit_offset: 0
                bit_length: 8
              - name: delay_s
                data_type: uint
                required: false
                default_value: 5
                bit_offset: 8
                bit_length: 8
        """
      end

    source =
      Source.new(%{
        artifact_id: Ids.new("authoring_model"),
        organization_id: org,
        mission_id: mission,
        catalog_family: :combined,
        artifact_name: "commands.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: "commands:\n" <> Enum.join(commands)
      })

    {:ok, imported} =
      CadenceYamlDatabase.import(source, %{import_run_id: Ids.new("authoring_import")})

    {:ok, compilation} = MissionModels.compile_layers(imported.bundle.declaration_layers)

    MissionModelFixtures.activate_imported_model!(org, mission, %{
      "mission_model" => %{"revision_id" => compilation.revision.revision_id}
    })
  end
end
