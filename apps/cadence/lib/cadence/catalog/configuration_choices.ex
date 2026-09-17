defmodule Cadence.Catalog.ConfigurationChoices do
  @moduledoc "Bounded catalog summaries for spacecraft setup without hydrating model documents."
  import Ecto.Query
  alias Cadence.Catalog.DatabaseRow
  alias Cadence.Repo

  def list(mission, selected_ids \\ []) do
    selected_ids = Enum.reject(selected_ids, &is_nil/1) |> Enum.uniq()

    from(revision in Cadence.Catalog.RevisionRow,
      join: database in DatabaseRow,
      on: database.catalog_database_id == revision.catalog_database_id,
      join: model in Cadence.MissionModels.RevisionRow,
      on: model.revision_id == revision.mission_model_revision_id,
      where:
        revision.organization_id == ^mission.organization_id and
          revision.mission_id == ^mission.mission_id,
      order_by: [
        desc: revision.catalog_revision_id in ^selected_ids,
        desc: revision.inserted_at,
        asc: revision.catalog_revision_id
      ],
      limit: 100,
      select: %{
        id: revision.catalog_revision_id,
        name: database.name,
        label: revision.revision_label,
        model_id: model.revision_id,
        declarations: model.declaration_count
      }
    )
    |> Repo.all()
    |> Enum.map(fn revision ->
      counts = counts(mission, revision.model_id)

      revision
      |> Map.drop([:model_id])
      |> Map.merge(counts)
      |> Map.put(:href, "/missions/#{mission.mission_id}/catalog/revisions/#{revision.id}")
    end)
  end

  defp counts(mission, revision_id) do
    rows =
      from(plan in Cadence.MissionModels.RuntimePlanRow,
        where:
          plan.organization_id == ^mission.organization_id and
            plan.mission_id == ^mission.mission_id and plan.revision_id == ^revision_id and
            plan.target in ["telemetry", "command"],
        select:
          {plan.target,
           fragment(
             "COALESCE(jsonb_array_length(? #> '{value,plan,packet_definitions}'), 0)",
             plan.plan_document
           ),
           fragment(
             "COALESCE(jsonb_array_length(? #> '{value,plan,runtime_definitions}'), 0)",
             plan.plan_document
           )}
      )
      |> Repo.all()

    %{
      packets: Enum.reduce(rows, 0, fn {_, packets, _}, total -> total + packets end),
      commands: Enum.reduce(rows, 0, fn {_, _, commands}, total -> total + commands end)
    }
  end
end
