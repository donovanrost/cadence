defmodule Cadence.Catalog.ModelImporters do
  @moduledoc """
  Who imported a mission-model revision (`Catalog.model_importers/3`): the people the model
  approval's importer/approver separation (`MissionModels.RevisionDecisions`, DECISIONS #92 a)
  and its read (`Reads.MissionModelApprovals`) count. Deduplicated user ids, the union of:

  - the users recorded as `created_by` on the catalog revisions that name the model revision
    (`"user_id"`, or `"id"` as before), and
  - the requesters of COMPLETED import runs, in that organization and mission, whose result names
    it (director/lead 11-17, option A). Every import run makes its own model revision (the
    declarations' provenance carries the run id), so a reimport, which makes no catalog revision,
    makes a model revision only its run names: whoever ran it is its importer. A reimport never
    changes the original revision's importers. A run's requester counts only when it is a user
    actor (`"actor_kind" => "user"` with its `"user_id"`), so a service or system actor
    (`Catalog.Actor`) never does; a failed run counts no one.

  Empty when no importer was recorded. Both columns are `JsonDocument`-wrapped (`{"value": …}`).
  """

  import Ecto.Query

  alias Cadence.Catalog.{ImportRunRow, RevisionRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @spec list(binary(), binary(), binary()) :: [binary()]
  def list(organization_id, mission_id, mission_model_revision_id) do
    revisions =
      from(row in RevisionRow,
        where:
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.mission_model_revision_id == ^mission_model_revision_id,
        select: row.created_by
      )
      |> Repo.all()
      |> Enum.map(&revision_importer/1)

    runs =
      from(run in ImportRunRow,
        where:
          run.organization_id == ^organization_id and run.mission_id == ^mission_id and
            run.status == "completed" and
            fragment(
              "? -> 'value' -> 'mission_model' ->> 'revision_id' = ?",
              run.result_document,
              ^mission_model_revision_id
            ),
        select: run.requested_by
      )
      |> Repo.all()
      |> Enum.map(&run_importer/1)

    (revisions ++ runs) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp revision_importer(created_by) do
    case JsonDocument.unwrap_value(created_by) do
      %{"user_id" => id} when is_binary(id) and id != "" -> id
      %{"id" => id} when is_binary(id) and id != "" -> id
      _not_recorded -> nil
    end
  end

  defp run_importer(requested_by) do
    case JsonDocument.unwrap_value(requested_by) do
      %{"actor_kind" => "user", "user_id" => id} when is_binary(id) and id != "" -> id
      _not_a_person -> nil
    end
  end
end
