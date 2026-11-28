defmodule Cadence.Reads.CatalogOverview do
  @moduledoc """
  Catalog reads for the Setup console: the index (databases, the selected
  database's revisions and recent import runs) and one import run's detail
  with diagnostics. Callers authorize first.

  Per-revision `spacecraft_count` counts spacecraft whose latest saved
  configuration references the revision. Per-kind declaration counts and the
  revision diff are not produced by the importers yet, so they are `nil`.
  """

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, ImportRun, Revision}
  alias Cadence.Catalog.CompositionPins
  alias Cadence.MissionModels
  alias Cadence.MissionModels.CompositionViews
  alias Cadence.Reads.Catalog.{Requesters, RevisionBase}
  alias Cadence.Reads.CatalogDiff

  @revision_limit 50
  @run_limit 20

  @spec index(binary(), binary(), binary() | nil) :: map()
  def index(organization_id, mission_id, database_id) do
    databases = Catalog.list_databases(organization_id, mission_id)

    selected =
      Enum.find(databases, &(&1.catalog_database_id == database_id)) || List.first(databases)

    %{
      databases:
        Enum.map(databases, &%{id: &1.catalog_database_id, name: &1.name, slug: &1.slug}),
      database: selected && database(organization_id, mission_id, selected)
    }
  end

  @spec import_run(binary(), binary(), binary()) :: {:ok, map()} | {:error, :import_run_not_found}
  def import_run(organization_id, mission_id, import_run_id) do
    case Catalog.fetch_import_run(organization_id, mission_id, import_run_id) do
      {:ok, %ImportRun{} = run} -> {:ok, run_detail(organization_id, mission_id, run)}
      {:error, _not_found} -> {:error, :import_run_not_found}
    end
  end

  @doc """
  K1 (L18): one source file, the revisions made from it and its import runs (newest first, 50).
  """
  @spec artifact(binary(), binary(), binary()) :: {:ok, map()} | {:error, :artifact_not_found}
  def artifact(organization_id, mission_id, artifact_id) do
    case Catalog.fetch_artifact(organization_id, mission_id, artifact_id) do
      {:ok, %Artifact{} = artifact} ->
        {:ok, artifact_detail(organization_id, mission_id, artifact)}

      {:error, _not_found} ->
        {:error, :artifact_not_found}
    end
  end

  @doc "The console download link of a source file (K3)."
  @spec download_url(binary(), binary() | nil) :: binary() | nil
  def download_url(_mission_id, nil), do: nil

  def download_url(mission_id, artifact_id),
    do: "/api/v1/missions/#{mission_id}/catalog/artifacts/#{artifact_id}/download"

  defp artifact_detail(organization_id, mission_id, artifact) do
    labels = importer_labels()

    runs =
      Catalog.list_import_runs(organization_id, mission_id, artifact_id: artifact.artifact_id)

    runs_by_id = Map.new(runs, &{&1.import_run_id, &1})
    usage = usage_by_revision(organization_id, mission_id)

    revisions =
      organization_id
      |> Catalog.list_revisions(mission_id, artifact.catalog_database_id)
      |> Enum.filter(&(&1.artifact_id == artifact.artifact_id))
      |> Enum.map(&revision(&1, Map.get(runs_by_id, &1.import_run_id), usage, labels, mission_id))
      |> named_actors(organization_id)

    revision_by_run = Map.new(revisions, &{&1.import_run_id, &1})

    database =
      organization_id
      |> Catalog.list_databases(mission_id)
      |> Enum.find(&(&1.catalog_database_id == artifact.catalog_database_id))

    %{
      artifact: %{
        id: artifact.artifact_id,
        file_name: artifact.artifact_name,
        format_label: Map.get(labels, artifact.format_key),
        format_version: artifact.format_version,
        media_type: artifact.media_type,
        size_bytes: size(artifact.source_artifact),
        sha256: artifact.content_sha256,
        uploaded_at: artifact.uploaded_at,
        uploaded_by: named(organization_id, artifact.uploaded_by),
        database: database && %{id: database.catalog_database_id, name: database.name},
        download_url: download_url(mission_id, artifact.artifact_id)
      },
      revisions: Enum.map(revisions, &Map.take(&1, [:id, :number, :label, :imported_at])),
      import_runs:
        run_rows(
          organization_id,
          Enum.take(runs, 50),
          revision_by_run,
          labels,
          %{artifact.artifact_id => artifact}
        )
    }
  end

  defp database(organization_id, mission_id, database) do
    id = database.catalog_database_id
    labels = importer_labels()

    runs =
      Catalog.list_import_runs(organization_id, mission_id, catalog_database_id: id)

    runs_by_id = Map.new(runs, &{&1.import_run_id, &1})
    usage = usage_by_revision(organization_id, mission_id)

    revisions =
      organization_id
      |> Catalog.list_revisions(mission_id, id)
      |> Enum.take(@revision_limit)
      |> Enum.map(&revision(&1, Map.get(runs_by_id, &1.import_run_id), usage, labels, mission_id))
      |> named_actors(organization_id)

    revision_by_run = Map.new(revisions, &{&1.import_run_id, &1})
    revisions = with_model_status(revisions, organization_id, mission_id)
    runs = Enum.take(runs, @run_limit)

    %{
      id: id,
      current_revision: current(organization_id, mission_id, List.first(revisions)),
      revisions: Enum.map(revisions, &Map.drop(&1, [:import_run_id, :model_revision_id])),
      import_runs:
        run_rows(
          organization_id,
          runs,
          revision_by_run,
          labels,
          artifacts_by_id(organization_id, mission_id, runs)
        )
    }
  end

  # U65 (fe-ops): each catalog revision's mission model and its approval status, for the row tag
  # (NEEDS APPROVAL / APPROVED / REJECTED); one batched status lookup. D2 (#543): and the id of
  # the composition behind that model revision (nil without one), one batched link lookup.
  defp with_model_status(revisions, organization_id, mission_id) do
    ids = revisions |> Enum.map(& &1.model_revision_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    statuses = MissionModels.revision_statuses(organization_id, mission_id, ids)
    compositions = CompositionViews.ids_for_revisions(organization_id, mission_id, ids)

    Enum.map(revisions, fn %{model_revision_id: id} = revision ->
      Map.merge(revision, %{
        model: model(id, statuses),
        composition_id: Map.get(compositions, id)
      })
    end)
  end

  defp model(nil, _statuses), do: nil
  defp model(id, statuses), do: %{revision_id: id, status: Map.get(statuses, id)}

  defp revision(%Revision{} = revision, run, usage, labels, mission_id) do
    metadata = revision.metadata || %{}

    %{
      id: revision.catalog_revision_id,
      number: revision.revision_number,
      label: revision.revision_label,
      notes: revision.notes,
      artifact: %{
        id: revision.artifact_id,
        file_name: metadata["source_artifact_name"],
        format_label: Map.get(labels, metadata["importer_key"]),
        size_bytes: nil,
        download_url: download_url(mission_id, revision.artifact_id)
      },
      declaration_count: run && run.imported_definition_count,
      command_count: nil,
      telemetry_count: nil,
      spacecraft_count: Map.get(usage, revision.catalog_revision_id, 0),
      imported_at: run && run.completed_at,
      # Named after the list is built (named_actors/2), one batched lookup.
      actor: revision.created_by,
      import_run_id: revision.import_run_id,
      model_revision_id: revision.mission_model_revision_id
    }
  end

  defp current(_organization_id, _mission_id, nil), do: nil

  # The current revision's per-kind counts come from its declarations (CatalogDiff.counts/3).
  defp current(organization_id, mission_id, revision) do
    {commands, telemetry} =
      CatalogDiff.counts(organization_id, mission_id, revision.model_revision_id)

    %{current_fields(revision) | command_count: commands, telemetry_count: telemetry}
  end

  defp current_fields(revision),
    do:
      Map.take(revision, [
        :id,
        :number,
        :label,
        :declaration_count,
        :command_count,
        :telemetry_count,
        :spacecraft_count,
        # #752: what a profile pins for this revision (D3), without listing every revision.
        :composition_id
      ])

  # #146 (U103): each row's requested_by, from two batched name queries per table.
  defp run_rows(organization_id, runs, revision_by_run, labels, artifacts_by_id) do
    names = Requesters.names(organization_id, Enum.map(runs, & &1.requested_by))
    Enum.map(runs, &run_row(&1, revision_by_run, labels, names, artifacts_by_id))
  end

  # A run names its own source file, so a failed or running run (no revision yet) still has one.
  defp artifacts_by_id(organization_id, mission_id, runs) do
    ids = runs |> Enum.map(& &1.artifact_id) |> Enum.uniq()

    organization_id
    |> Catalog.list_artifacts(mission_id, artifact_ids: ids)
    |> Map.new(&{&1.artifact_id, &1})
  end

  defp run_row(%ImportRun{} = run, revision_by_run, labels, names, artifacts_by_id) do
    artifact = Map.get(artifacts_by_id, run.artifact_id)

    %{
      id: run.import_run_id,
      file_name: artifact && artifact.artifact_name,
      format_label: artifact && Map.get(labels, artifact.format_key),
      status: status(run.status),
      diagnostic_counts: diagnostic_counts(run.diagnostics),
      revision_number: revision_by_run |> Map.get(run.import_run_id, %{}) |> Map.get(:number),
      started_at: run.started_at,
      completed_at: run.completed_at,
      requested_by: Requesters.requested_by(run.requested_by, names)
    }
  end

  defp run_detail(organization_id, mission_id, %ImportRun{} = run) do
    artifact =
      case Catalog.fetch_artifact(organization_id, mission_id, run.artifact_id) do
        {:ok, %Artifact{} = artifact} -> artifact
        _missing -> nil
      end

    revision =
      case Catalog.fetch_revision_by_import_run(organization_id, mission_id, run.import_run_id) do
        {:ok, %Revision{} = revision} -> revision
        _none -> nil
      end

    %{
      id: run.import_run_id,
      status: status(run.status),
      started_at: run.started_at,
      completed_at: run.completed_at,
      requested_by:
        Requesters.requested_by(
          run.requested_by,
          Requesters.names(organization_id, [run.requested_by])
        ),
      file: %{
        name: artifact && artifact.artifact_name,
        format_label: Map.get(importer_labels(), run.importer_key),
        size_bytes: artifact && size(artifact.source_artifact),
        artifact:
          artifact &&
            %{
              id: artifact.artifact_id,
              download_url: download_url(mission_id, artifact.artifact_id)
            }
      },
      declaration_count: run.imported_definition_count,
      failure_reason: failure_reason(run.failure_reason),
      diagnostics: Enum.map(run.diagnostics || [], &diagnostic/1)
    }
    |> Map.merge(revision_fields(organization_id, mission_id, revision))
  end

  # C3's revision, the revision before it in its database, and the diff between them.
  defp revision_fields(_organization_id, _mission_id, nil),
    do: %{revision: nil, base_revision: nil, diff: nil}

  defp revision_fields(organization_id, mission_id, %Revision{} = revision) do
    base = RevisionBase.previous(organization_id, mission_id, revision)

    %{
      revision: %{
        id: revision.catalog_revision_id,
        number: revision.revision_number,
        label: revision.revision_label,
        # D3 (#544): what C3 pins; a rollout stages this composition, never the catalog revision.
        composition_id: composition_id(organization_id, mission_id, revision)
      },
      base_revision: base && %{id: base.catalog_revision_id, number: base.revision_number},
      diff:
        base &&
          CatalogDiff.diff(
            organization_id,
            mission_id,
            base.mission_model_revision_id,
            revision.mission_model_revision_id
          )
    }
  end

  defp composition_id(organization_id, mission_id, %Revision{catalog_revision_id: id}) do
    case CompositionPins.for_catalog_revision(organization_id, mission_id, id) do
      {:ok, composition_id} -> composition_id
      {:error, :none} -> nil
    end
  end

  defp diagnostic(diagnostic) do
    path = Map.get(diagnostic, :path) || []

    %{
      severity: Map.get(diagnostic, :severity),
      code: Map.get(diagnostic, :code),
      message: Map.get(diagnostic, :message),
      path: if(path == [], do: nil, else: Enum.join(List.wrap(path), " / "))
    }
  end

  defp diagnostic_counts(diagnostics) do
    counts = Enum.frequencies_by(diagnostics || [], &Map.get(&1, :severity))

    %{
      error: Map.get(counts, :error, 0),
      warning: Map.get(counts, :warning, 0),
      info: Map.get(counts, :info, 0)
    }
  end

  defp usage_by_revision(organization_id, mission_id) do
    organization_id
    |> Drafts.catalog_usage_entries(mission_id)
    |> Enum.frequencies_by(& &1.catalog_revision_id)
  end

  defp importer_labels do
    Map.new(Catalog.list_importers(), fn %{descriptor: descriptor} ->
      {descriptor.importer_key, descriptor.display_name}
    end)
  end

  defp status(:running), do: :running
  defp status(:completed), do: :succeeded
  defp status(:failed), do: :failed
  defp status(other), do: other

  defp failure_reason(nil), do: nil
  defp failure_reason(reason) when is_binary(reason), do: reason
  defp failure_reason(reason), do: inspect(reason)

  defp size(bytes) when is_binary(bytes), do: byte_size(bytes)
  defp size(_other), do: nil

  # #366 (mms-security, #146's rule): who uploaded a file or made a revision is named as import
  # runs' requested_by is (Requesters): a person only while an active member of the mission's
  # organization, a service only when it belongs to it, Cadence by its system name. The name or
  # email stored in the actor document is never sent. `{kind, name}`, or nil with no actor.
  defp named(organization_id, by),
    do: Requesters.requested_by(by, Requesters.names(organization_id, [by]))

  defp named_actors(revisions, organization_id) do
    names = Requesters.names(organization_id, Enum.map(revisions, & &1.actor))
    Enum.map(revisions, &%{&1 | actor: Requesters.requested_by(&1.actor, names)})
  end
end
