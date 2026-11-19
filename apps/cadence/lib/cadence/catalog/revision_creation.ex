defmodule Cadence.Catalog.RevisionCreation do
  @moduledoc """
  The catalog revision a completed import run makes (moved out of `Cadence.Catalog`, #119): one
  per run, idempotent on a rerun (director 11-14), numbered under the catalog database's row lock
  (domain), and none for an upload whose content matches a revision that database already names
  (#119, decided under the same lock).
  """

  import Ecto.Query

  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Database, DatabaseRow, Facts, ImportRun, MatchedImport}
  alias Cadence.Catalog.{Revision, RevisionRow}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Repo
  alias Ecto.Changeset

  @doc """
  Attaches the catalog revision a completed revision-making run produced, recording it in the
  run's result; an upload matching a revision this catalog database already names makes none
  (#119, `MatchedImport`). A failure to make it fails the run.
  """
  @spec attach(ImportRun.t(), term()) :: ImportRun.t()
  def attach(%ImportRun{} = run, event_bus) do
    case MatchedImport.revision_for(run) do
      :none -> run
      {:matched, revision} -> MatchedImport.record(run, revision)
      {:create, run} -> attach_created_revision(run, event_bus)
    end
  end

  defp attach_created_revision(run, event_bus) do
    case create_revision_from_completed_run(run, event_bus) do
      {:ok, {:matched, revision}} ->
        MatchedImport.record(run, revision)

      {:ok, %Revision{} = revision} ->
        %ImportRun{
          run
          | result_document:
              Map.put(run.result_document || %{}, "catalog_revision", %{
                "catalog_revision_id" => revision.catalog_revision_id,
                "catalog_database_id" => revision.catalog_database_id,
                "revision_number" => revision.revision_number,
                "revision_label" => revision.revision_label
              })
        }

      {:error, reason} ->
        %ImportRun{
          run
          | status: :failed,
            failure_reason: {:catalog_revision_creation_failed, reason}
        }
    end
  end

  # Idempotent (director 11-14): a rerun of the same import run finds the revision it already
  # made instead of inserting a second (which the unique index on import_run_id refused, failing
  # a completed run). The revision and its operational event commit together; the fact is
  # published after the commit.
  defp create_revision_from_completed_run(%ImportRun{} = run, event_bus) do
    case Catalog.fetch_revision_by_import_run(
           run.organization_id,
           run.mission_id,
           run.import_run_id
         ) do
      # Published again (domain): a node that stopped between the commit and the publish lost
      # the fact; its one consumer is an idempotent dashboard cache invalidation.
      {:ok, %Revision{} = revision} ->
        Facts.publish(event_bus, revision)
        {:ok, revision}

      {:error, :catalog_revision_not_found} ->
        with {:ok, %Revision{} = revision} <- insert_revision_from_completed_run(run) do
          Facts.publish(event_bus, revision)
          {:ok, revision}
        end
    end
  end

  defp insert_revision_from_completed_run(%ImportRun{} = run) do
    with {:ok, %Artifact{} = artifact} <-
           Catalog.fetch_artifact(run.organization_id, run.mission_id, run.artifact_id),
         {:ok, %Database{} = database} <-
           Catalog.fetch_database(run.organization_id, run.mission_id, run.catalog_database_id),
         mission_model_revision_id <-
           run.result_document
           |> metadata_value("mission_model")
           |> metadata_value("revision_id"),
         :ok <- ensure_revision_basis(mission_model_revision_id),
         attrs <-
           %{
             organization_id: run.organization_id,
             mission_id: run.mission_id,
             catalog_database_id: run.catalog_database_id,
             catalog_family: database.catalog_family,
             artifact_id: artifact.artifact_id,
             import_run_id: run.import_run_id,
             mission_model_layer_id:
               run.result_document
               |> metadata_value("mission_model")
               |> metadata_value("layer_ids")
               |> first_value(),
             mission_model_revision_id: mission_model_revision_id,
             content_sha256: artifact.content_sha256,
             created_by: run.requested_by,
             notes: metadata_value(run.metadata, "revision_notes"),
             metadata: %{
               "source_artifact_name" => artifact.artifact_name,
               "importer_key" => run.importer_key
             }
           },
         {:ok, revision} <- persist_revision(run, attrs) do
      {:ok, revision}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  # The database row is locked while the next number and label are chosen (domain): two runs
  # on one database at once take turns instead of one failing on the unique
  # (catalog_database_id, revision_number) index.
  defp persist_revision(%ImportRun{} = run, attrs) do
    Repo.transaction(fn ->
      _locked = lock_database(run.catalog_database_id)

      # Under the lock, again (domain): two reruns of the same import run at once both miss the
      # check before the lock; the second must find the first's revision, not insert another.
      case Catalog.fetch_revision_by_import_run(
             run.organization_id,
             run.mission_id,
             run.import_run_id
           ) do
        {:ok, %Revision{} = existing} ->
          existing

        # #119: a match is decided under the same lock, so two identical uploads can't both insert.
        {:error, :catalog_revision_not_found} ->
          MatchedImport.match_under_lock(run) || insert_locked_revision(run, attrs)
      end
    end)
  end

  defp insert_locked_revision(%ImportRun{} = run, attrs) do
    revision_number = next_revision_number(run.catalog_database_id)

    revision =
      attrs
      |> Map.merge(%{
        revision_number: revision_number,
        revision_label: revision_label(run, revision_number)
      })
      |> Revision.new()

    with {:ok, %RevisionRow{} = row} <- Repo.insert(RevisionRow.changeset(revision)),
         revision = RevisionRow.to_domain(row),
         {:ok, %OperationalEvent{}} <-
           revision
           |> OperationalEvent.from_catalog_revision(row.inserted_at)
           |> then(&OperationalEvents.persist_event(Repo, &1)) do
      revision
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_database(catalog_database_id) do
    from(row in DatabaseRow,
      where: row.catalog_database_id == ^catalog_database_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp ensure_revision_basis(revision_id) when is_binary(revision_id) and revision_id != "",
    do: :ok

  defp ensure_revision_basis(_revision_id), do: {:error, :catalog_revision_requires_model}

  defp next_revision_number(catalog_database_id) do
    query =
      from(row in RevisionRow,
        where: row.catalog_database_id == ^catalog_database_id,
        select: max(row.revision_number)
      )

    case Repo.one(query) do
      nil -> 1
      number -> number + 1
    end
  end

  defp revision_label(%ImportRun{} = run, revision_number) do
    run.metadata
    |> metadata_value("revision_label")
    |> case do
      nil -> "Revision #{revision_number}"
      "" -> "Revision #{revision_number}"
      label -> label
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_binary(key) do
    Map.get(metadata, key) || Map.get(metadata, metadata_atom_key(key))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp first_value([value | _rest]), do: value
  defp first_value(_other), do: nil

  defp metadata_atom_key("revision_label"), do: :revision_label
  defp metadata_atom_key("revision_notes"), do: :revision_notes
  defp metadata_atom_key(_key), do: nil
end
