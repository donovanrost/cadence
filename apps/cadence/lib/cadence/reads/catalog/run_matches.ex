defmodule Cadence.Reads.Catalog.RunMatches do
  @moduledoc """
  The import runs table's `matched` (#119, ux U99): for a completed run whose content matched a
  mission-model revision that already existed,
  `%{number, status, model_revision_id, first: %{number, database: %{id, name}} | nil}`, else `nil`.

  - `number`: the catalog revision of THIS database that names the match (`nil` when none does).
  - `status`: the model revision's CURRENT status, so the tag shows a later decision.
  - `model_revision_id`: a route parameter only, never a sentence.
  - `first`: the catalog revision the model is first recorded under (U65), with its database, for
    "Same as Bus catalog rev 4" when the run made its own revision in another database.

  Four batched queries per table, whatever its length (statuses, this database's numbers, the
  first-recorded revisions, the mission's database names).
  """

  alias Cadence.Catalog
  alias Cadence.Catalog.{ImportRun, ModelRevisions}
  alias Cadence.MissionModels

  @doc "Puts `:matched` on each run row (`%{id: run_id}`), from `runs`."
  @spec put([map()], [ImportRun.t()], binary(), binary(), binary()) :: [map()]
  def put(rows, runs, organization_id, mission_id, database_id) do
    models =
      for %ImportRun{} = run <- runs, id = matched_model(run), into: %{} do
        {run.import_run_id, id}
      end

    ids = models |> Map.values() |> Enum.uniq()

    found = %{
      statuses: MissionModels.revision_statuses(organization_id, mission_id, ids),
      numbers: ModelRevisions.numbers_in_database(organization_id, mission_id, database_id, ids),
      first: first_recorded(organization_id, mission_id, ids)
    }

    Enum.map(rows, &Map.put(&1, :matched, matched(Map.get(models, &1.id), found)))
  end

  defp matched_model(%ImportRun{status: :completed, result_document: %{} = document}) do
    case get_in(document, ["mission_model", "matched_existing", "revision_id"]) do
      id when is_binary(id) -> id
      _new_revision -> nil
    end
  end

  defp matched_model(%ImportRun{}), do: nil

  # A matched revision this read can't find in its mission reads as no match, never as another's.
  defp matched(nil, _found), do: nil

  defp matched(model_id, found) do
    case Map.fetch(found.statuses, model_id) do
      {:ok, status} ->
        %{
          number: Map.get(found.numbers, model_id),
          status: Atom.to_string(status),
          model_revision_id: model_id,
          first: Map.get(found.first, model_id)
        }

      :error ->
        nil
    end
  end

  defp first_recorded(_organization_id, _mission_id, []), do: %{}

  defp first_recorded(organization_id, mission_id, model_ids) do
    revisions = ModelRevisions.for_models(organization_id, mission_id, model_ids)

    names =
      if revisions == %{},
        do: %{},
        else:
          organization_id
          |> Catalog.list_databases(mission_id)
          |> Map.new(&{&1.catalog_database_id, &1.name})

    Map.new(revisions, fn {model, revision} ->
      database = %{id: revision.database_id, name: Map.get(names, revision.database_id)}
      {model, %{number: revision.number, database: database}}
    end)
  end
end
