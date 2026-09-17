defmodule Cadence.Reads.Catalog.Revisions do
  @moduledoc false

  import Cadence.Reads.Catalog.Presentation

  alias Cadence.Catalog
  alias Cadence.Missions
  alias Cadence.Reads.Catalog.SpacecraftUsage

  def catalog_revision_show(organization_id, mission_id, params) do
    with {:ok, revision_id} <- subject_id(params, "catalog_revision_id"),
         {:ok, revision} <- Catalog.fetch_revision(organization_id, mission_id, revision_id),
         {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, spacecraft_usage} <- SpacecraftUsage.load(mission, revision_id) do
      database =
        optional(fn ->
          Catalog.fetch_database(organization_id, mission_id, revision.catalog_database_id)
        end)

      artifact =
        optional(fn ->
          Catalog.fetch_artifact(organization_id, mission_id, revision.artifact_id)
        end)

      run =
        optional(fn ->
          Catalog.fetch_import_run(organization_id, mission_id, revision.import_run_id)
        end)

      model =
        optional(fn ->
          Cadence.MissionModels.fetch_revision(
            organization_id,
            mission_id,
            revision.mission_model_revision_id
          )
        end)

      plans =
        optional(fn ->
          Cadence.MissionModels.fetch_runtime_plans(
            organization_id,
            mission_id,
            revision.mission_model_revision_id
          )
        end) || %{}

      navigation =
        [
          %{"label" => "Mission", "href" => mission_href(mission_id)},
          %{"label" => "Catalog", "href" => "/missions/#{mission_id}/catalog"}
        ] ++
          if(database,
            do: [
              %{
                "label" => database.name,
                "href" =>
                  "/missions/#{mission_id}/catalog/databases/#{database.catalog_database_id}"
              }
            ],
            else: []
          ) ++ [%{"label" => revision.revision_label, "href" => nil}]

      {:ok,
       %{
         "revision" => %{
           "title" => revision.revision_label,
           "number_label" => "Revision #{revision.revision_number}"
         },
         "navigation" => %{"breadcrumbs" => navigation},
         "provenance" => %{
           "id" => "catalog-revision-provenance",
           "title" => "Revision provenance",
           "rows" => [
             %{
               "label" => "Database",
               "value" => database && database.name,
               "href" => nil,
               "style" => "default"
             },
             %{
               "label" => "Artifact",
               "value" => artifact && artifact.artifact_name,
               "href" =>
                 artifact && "/missions/#{mission_id}/catalog/artifacts/#{artifact.artifact_id}",
               "style" => "default"
             },
             %{
               "label" => "Import run",
               "value" => run && run.import_run_id,
               "href" => run && "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}",
               "style" => "mono"
             },
             %{
               "label" => "Content SHA-256",
               "value" => revision.content_sha256,
               "href" => nil,
               "style" => "hash"
             }
           ]
         },
         "spacecraft_usage" => spacecraft_usage,
         "mission_model" => mission_model_dto(model, plans)
       }}
    end
  end

  defp mission_model_dto(nil, _plans),
    do: %{
      "id" => "catalog-mission-model",
      "title" => "Mission Model",
      "available" => false,
      "empty_message" => "Mission Model unavailable.",
      "rows" => []
    }

  defp mission_model_dto(model, plans),
    do: %{
      "id" => "catalog-mission-model",
      "title" => "Mission Model",
      "available" => true,
      "empty_message" => "Mission Model unavailable.",
      "rows" => [
        %{"label" => "Revision", "value" => model.revision_id, "href" => nil, "style" => "hash"},
        %{
          "label" => "Declarations",
          "value" => map_size(model.declarations),
          "href" => nil,
          "style" => "default"
        },
        %{
          "label" => "Space systems",
          "value" => map_size(model.space_systems),
          "href" => nil,
          "style" => "default"
        },
        %{
          "label" => "Ready plans",
          "value" => Enum.count(plans, fn {_target, plan} -> plan.status == :ready end),
          "href" => nil,
          "style" => "default"
        }
      ]
    }
end
