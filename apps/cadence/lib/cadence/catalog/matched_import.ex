defmodule Cadence.Catalog.MatchedImport do
  @moduledoc """
  Whether a completed import run makes a catalog revision (#119, domain's ruling 11-19).

  Identical content is one mission-model revision. An upload whose model revision MATCHED one
  that a revision of the SAME catalog database already names makes no catalog revision: the
  catalog keeps one revision per distinct content, so no "rev 5" is secretly rev 4. The run still
  completes, keeps its artifact and requester (an importer through `Catalog.ModelImporters`), and
  its result names the matched catalog revision. Uploaded into a DIFFERENT catalog database, the
  same content makes that database's own revision naming the existing model revision, so that
  catalog's model stays named (the orphan guard, `Catalog.ModelRevisionNaming`).
  """

  import Ecto.Query

  alias Cadence.Catalog.{ImportRun, Revision, RevisionRow}
  alias Cadence.Repo

  @doc """
  `:none` (no revision: not a revision-making run), `{:matched, revision}` (the same database's
  revision that already names the matched model revision), or `{:create, run}`. A run that
  already made its own revision (a rerun, director 11-14) creates (finding it again), and the
  model it compiled on its first pass is its own, not a match, so `matched_existing` is dropped.
  """
  @spec revision_for(ImportRun.t()) :: :none | {:create, ImportRun.t()} | {:matched, Revision.t()}
  def revision_for(%ImportRun{} = run) do
    cond do
      not creates_revision?(run) -> :none
      own_revision?(run) -> {:create, drop_match(run)}
      revision = named_in_database(run) -> {:matched, revision}
      true -> {:create, run}
    end
  end

  @doc "Records the matched catalog revision in the run's result (`matched_existing`)."
  @spec record(ImportRun.t(), Revision.t()) :: ImportRun.t()
  def record(%ImportRun{} = run, %Revision{} = revision) do
    catalog_revision = %{
      "catalog_revision_id" => revision.catalog_revision_id,
      "catalog_database_id" => revision.catalog_database_id,
      "revision_number" => revision.revision_number,
      "revision_label" => revision.revision_label
    }

    %ImportRun{
      run
      | result_document:
          update_in(
            run.result_document,
            ["mission_model", "matched_existing"],
            &Map.put(&1, "catalog_revision", catalog_revision)
          )
    }
  end

  defp own_revision?(%ImportRun{} = run) do
    Repo.exists?(
      from(row in RevisionRow,
        where:
          row.organization_id == ^run.organization_id and row.mission_id == ^run.mission_id and
            row.import_run_id == ^run.import_run_id
      )
    )
  end

  defp drop_match(
         %ImportRun{result_document: %{"mission_model" => %{} = model} = document} = run
       ),
       do: %ImportRun{
         run
         | result_document: %{document | "mission_model" => %{model | "matched_existing" => nil}}
       }

  defp drop_match(run), do: run

  defp creates_revision?(%ImportRun{catalog_database_id: nil}), do: false

  defp creates_revision?(%ImportRun{metadata: metadata}) when is_map(metadata),
    do:
      Map.get(metadata, "create_revision") == true or Map.get(metadata, :create_revision) == true

  defp creates_revision?(%ImportRun{}), do: false

  defp named_in_database(%ImportRun{} = run) do
    case get_in(run.result_document || %{}, ["mission_model", "matched_existing", "revision_id"]) do
      model_id when is_binary(model_id) ->
        from(row in RevisionRow,
          where:
            row.organization_id == ^run.organization_id and row.mission_id == ^run.mission_id and
              row.catalog_database_id == ^run.catalog_database_id and
              row.mission_model_revision_id == ^model_id,
          order_by: [asc: row.inserted_at, asc: row.catalog_revision_id],
          limit: 1
        )
        |> Repo.one()
        |> then(&(&1 && RevisionRow.to_domain(&1)))

      _new_content ->
        nil
    end
  end
end
