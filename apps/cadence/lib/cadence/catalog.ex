defmodule Cadence.Catalog do
  @moduledoc """
  Shared catalog artifact and import-run infrastructure for telemetry and command
  catalog import.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Catalog.{
    Artifact,
    ArtifactRow,
    CommandSnapshotRow,
    Database,
    DatabaseRow,
    Events,
    ImportExecution,
    ImportResult,
    ImportRun,
    ImportRunRow,
    Registry,
    Revision,
    RevisionRow,
    Source,
    TelemetrySnapshotRow
  }

  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.{RuntimeArtifacts, RuntimeDiff}
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Governance
  alias Cadence.Jobs
  alias Cadence.Missions
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Repo

  @spec list_importers(keyword()) :: [%{module: module(), descriptor: map()}]
  def list_importers(opts \\ []) when is_list(opts) do
    Registry.list_importers(opts)
  end

  @spec create_database(binary(), binary(), map()) :: {:ok, Database.t()} | {:error, term()}
  def create_database(organization_id, mission_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(attrs) do
    database =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:mission_id, mission_id)
      |> Database.new()

    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, %DatabaseRow{} = row} <-
           Repo.insert(DatabaseRow.changeset(database)) do
      {:ok, DatabaseRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_database(binary(), binary(), binary(), map()) ::
          {:ok, Database.t()} | {:error, term()}
  def update_database(organization_id, mission_id, catalog_database_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_database_id) and is_map(attrs) do
    with {:ok, %Database{} = existing} <-
           fetch_database(organization_id, mission_id, catalog_database_id),
         updated <-
           Database.new(%{
             catalog_database_id: existing.catalog_database_id,
             organization_id: existing.organization_id,
             mission_id: existing.mission_id,
             name: Map.get(attrs, :name, existing.name),
             slug: Map.get(attrs, :slug, existing.slug),
             description: Map.get(attrs, :description, existing.description),
             catalog_family: Map.get(attrs, :catalog_family, existing.catalog_family),
             default_importer_key:
               Map.get(attrs, :default_importer_key, existing.default_importer_key),
             created_by: existing.created_by,
             metadata: Map.get(attrs, :metadata, existing.metadata)
           }),
         %DatabaseRow{} = row <- Repo.get(DatabaseRow, catalog_database_id),
         {:ok, %DatabaseRow{} = updated_row} <-
           Repo.update(DatabaseRow.changeset(row, updated)) do
      {:ok, DatabaseRow.to_domain(updated_row)}
    else
      nil -> {:error, :catalog_database_not_found}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_database(binary(), binary(), binary()) :: {:ok, Database.t()} | {:error, term()}
  def fetch_database(organization_id, mission_id, catalog_database_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_database_id) do
    case Repo.get_by(
           DatabaseRow,
           organization_id: organization_id,
           mission_id: mission_id,
           catalog_database_id: catalog_database_id
         ) do
      nil -> {:error, :catalog_database_not_found}
      %DatabaseRow{} = row -> {:ok, DatabaseRow.to_domain(row)}
    end
  end

  @spec list_databases(binary(), binary(), keyword()) :: [Database.t()]
  def list_databases(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    catalog_family = Keyword.get(opts, :catalog_family)

    DatabaseRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_catalog_family(catalog_family)
    |> order_by([row], asc: row.name, asc: row.catalog_database_id)
    |> Repo.all()
    |> Enum.map(&DatabaseRow.to_domain/1)
  end

  @spec persist_artifact(binary(), Artifact.t()) :: {:ok, Artifact.t()} | {:error, term()}
  def persist_artifact(organization_id, %Artifact{} = artifact) when is_binary(organization_id) do
    with {:ok, scoped_artifact} <- put_organization_scope(artifact, organization_id),
         {:ok, _mission} <- Missions.fetch_mission(organization_id, scoped_artifact.mission_id),
         :ok <-
           ensure_database_scope(
             organization_id,
             scoped_artifact.mission_id,
             scoped_artifact.catalog_database_id
           ),
         {:ok, _row} <-
           Repo.insert(ArtifactRow.changeset(scoped_artifact),
             on_conflict: :nothing,
             conflict_target: [:artifact_id]
           ) do
      {:ok, scoped_artifact}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_artifact(binary(), binary(), binary()) :: {:ok, Artifact.t()} | {:error, term()}
  def fetch_artifact(organization_id, mission_id, artifact_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(artifact_id) do
    case Repo.get_by(
           ArtifactRow,
           organization_id: organization_id,
           mission_id: mission_id,
           artifact_id: artifact_id
         ) do
      nil -> {:error, :catalog_artifact_not_found}
      %ArtifactRow{} = row -> {:ok, ArtifactRow.to_domain(row)}
    end
  end

  @spec list_artifacts(binary(), binary(), keyword()) :: [Artifact.t()]
  def list_artifacts(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    catalog_family = Keyword.get(opts, :catalog_family)
    catalog_database_id = Keyword.get(opts, :catalog_database_id)

    ArtifactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_catalog_family(catalog_family)
    |> maybe_filter_catalog_database_id(catalog_database_id)
    |> order_by([row], desc: row.uploaded_at, desc: row.artifact_id)
    |> Repo.all()
    |> Enum.map(&ArtifactRow.to_domain/1)
  end

  @spec start_import_run(binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, ImportRun.t()} | {:error, term()}
  def start_import_run(organization_id, mission_id, artifact_id, importer_key, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(artifact_id) and
             is_binary(importer_key) and is_list(opts) do
    with {:ok, %Artifact{} = artifact} <- fetch_artifact(organization_id, mission_id, artifact_id),
         {:ok, %{module: importer_module, descriptor: descriptor}} <-
           Registry.fetch_importer(importer_key, Keyword.get(opts, :importer_version, :latest)),
         :ok <- ensure_catalog_family_match(artifact.catalog_family, descriptor.catalog_family),
         catalog_database_id <-
           Keyword.get(opts, :catalog_database_id, artifact.catalog_database_id),
         :ok <- ensure_database_scope(organization_id, mission_id, catalog_database_id),
         :ok <- validate_artifact(importer_module, artifact),
         run <-
           build_run(
             %Artifact{artifact | catalog_database_id: catalog_database_id},
             descriptor,
             opts
           ),
         {:ok, %ImportRun{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :catalog_import_run,
             mission_id,
             persisted_run.import_run_id,
             %{"import_run_id" => persisted_run.import_run_id}
           ) do
        {:ok, _job} ->
          {:ok, persisted_run}

        {:error, reason} ->
          failed_run =
            %ImportRun{
              persisted_run
              | status: :failed,
                failure_reason: {:job_enqueue_failed, reason},
                completed_at: DateTime.utc_now()
            }

          _ = update_run(failed_run)
          {:error, reason}
      end
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, ImportRun.t()} | {:error, term()}
  def execute_enqueued_run(import_run_id) when is_binary(import_run_id) do
    with {:ok, %ImportRun{} = run} <- fetch_import_run_by_id(import_run_id),
         {:ok, %Artifact{} = artifact} <-
           fetch_artifact(run.organization_id, run.mission_id, run.artifact_id),
         {:ok, %{module: importer_module, descriptor: descriptor}} <-
           Registry.fetch_importer(run.importer_key, run.importer_version),
         :ok <- ensure_catalog_family_match(artifact.catalog_family, descriptor.catalog_family),
         :ok <- validate_artifact(importer_module, artifact) do
      execute_run(run, artifact, importer_module)
    end
  end

  @spec fetch_import_run(binary(), binary(), binary()) :: {:ok, ImportRun.t()} | {:error, term()}
  def fetch_import_run(organization_id, mission_id, import_run_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(import_run_id) do
    case Repo.get_by(
           ImportRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           import_run_id: import_run_id
         ) do
      nil -> {:error, :catalog_import_run_not_found}
      %ImportRunRow{} = row -> {:ok, ImportRunRow.to_domain(row)}
    end
  end

  @spec list_import_runs(binary(), binary(), keyword()) :: [ImportRun.t()]
  def list_import_runs(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    artifact_id = Keyword.get(opts, :artifact_id)
    catalog_database_id = Keyword.get(opts, :catalog_database_id)
    status = Keyword.get(opts, :status)

    ImportRunRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_catalog_database_id(catalog_database_id)
    |> maybe_filter_artifact_id(artifact_id)
    |> maybe_filter_status(status)
    |> order_by([row], desc: row.started_at, desc: row.import_run_id)
    |> Repo.all()
    |> Enum.map(&ImportRunRow.to_domain/1)
  end

  @spec latest_import_run_by_artifact(binary(), binary()) ::
          %{optional(binary()) => ImportRun.t()}
  def latest_import_run_by_artifact(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ImportRunRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], desc: row.started_at, desc: row.import_run_id)
    |> Repo.all()
    |> Enum.map(&ImportRunRow.to_domain/1)
    |> Enum.reduce(%{}, fn %ImportRun{artifact_id: artifact_id} = run, acc ->
      Map.put_new(acc, artifact_id, run)
    end)
  end

  @spec latest_import_run_by_database(binary(), binary()) :: %{
          optional(binary()) => ImportRun.t()
        }
  def latest_import_run_by_database(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ImportRunRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        not is_nil(row.catalog_database_id)
    )
    |> order_by([row], desc: row.started_at, desc: row.import_run_id)
    |> Repo.all()
    |> Enum.map(&ImportRunRow.to_domain/1)
    |> Enum.reduce(%{}, fn %ImportRun{catalog_database_id: catalog_database_id} = run, acc ->
      Map.put_new(acc, catalog_database_id, run)
    end)
  end

  @spec persist_telemetry_snapshot(binary(), TelemetryCatalogSnapshot.t()) ::
          {:ok, TelemetryCatalogSnapshot.t()} | {:error, term()}
  def persist_telemetry_snapshot(organization_id, %TelemetryCatalogSnapshot{} = snapshot)
      when is_binary(organization_id) do
    with {:ok, scoped_snapshot} <-
           put_telemetry_snapshot_organization_scope(snapshot, organization_id),
         {:ok, _mission} <- Missions.fetch_mission(organization_id, scoped_snapshot.mission_id),
         {:ok, _row} <-
           Repo.insert(TelemetrySnapshotRow.changeset(scoped_snapshot),
             on_conflict: :nothing,
             conflict_target: [:snapshot_id]
           ) do
      {:ok, scoped_snapshot}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_command_snapshot(binary(), CommandCatalogSnapshot.t()) ::
          {:ok, CommandCatalogSnapshot.t()} | {:error, term()}
  def persist_command_snapshot(organization_id, %CommandCatalogSnapshot{} = snapshot)
      when is_binary(organization_id) do
    with {:ok, scoped_snapshot} <-
           put_command_snapshot_organization_scope(snapshot, organization_id),
         {:ok, _mission} <- Missions.fetch_mission(organization_id, scoped_snapshot.mission_id),
         {:ok, _row} <-
           Repo.insert(CommandSnapshotRow.changeset(scoped_snapshot),
             on_conflict: :nothing,
             conflict_target: [:snapshot_id]
           ) do
      {:ok, scoped_snapshot}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_telemetry_snapshot(binary(), binary(), binary()) ::
          {:ok, TelemetryCatalogSnapshot.t()} | {:error, term()}
  def fetch_telemetry_snapshot(organization_id, mission_id, snapshot_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) do
    case Repo.get_by(
           TelemetrySnapshotRow,
           organization_id: organization_id,
           mission_id: mission_id,
           snapshot_id: snapshot_id
         ) do
      nil -> {:error, :catalog_telemetry_snapshot_not_found}
      %TelemetrySnapshotRow{} = row -> {:ok, TelemetrySnapshotRow.to_domain(row)}
    end
  end

  @spec list_telemetry_snapshots(binary(), binary(), keyword()) :: [TelemetryCatalogSnapshot.t()]
  def list_telemetry_snapshots(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    artifact_id = Keyword.get(opts, :artifact_id)
    import_run_id = Keyword.get(opts, :import_run_id)

    TelemetrySnapshotRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_artifact_id(artifact_id)
    |> maybe_filter_import_run_id(import_run_id)
    |> order_by([row], desc: row.inserted_at, desc: row.snapshot_id)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(&TelemetrySnapshotRow.to_domain/1)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, max) when is_integer(max) and max > 0, do: limit(query, ^max)

  @spec fetch_command_snapshot(binary(), binary(), binary()) ::
          {:ok, CommandCatalogSnapshot.t()} | {:error, term()}
  def fetch_command_snapshot(organization_id, mission_id, snapshot_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) do
    case Repo.get_by(
           CommandSnapshotRow,
           organization_id: organization_id,
           mission_id: mission_id,
           snapshot_id: snapshot_id
         ) do
      nil -> {:error, :catalog_command_snapshot_not_found}
      %CommandSnapshotRow{} = row -> {:ok, CommandSnapshotRow.to_domain(row)}
    end
  end

  @spec list_command_snapshots(binary(), binary(), keyword()) :: [CommandCatalogSnapshot.t()]
  def list_command_snapshots(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    artifact_id = Keyword.get(opts, :artifact_id)
    import_run_id = Keyword.get(opts, :import_run_id)

    CommandSnapshotRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_artifact_id(artifact_id)
    |> maybe_filter_import_run_id(import_run_id)
    |> order_by([row], desc: row.inserted_at, desc: row.snapshot_id)
    |> Repo.all()
    |> Enum.map(&CommandSnapshotRow.to_domain/1)
  end

  @spec fetch_revision(binary(), binary(), binary()) :: {:ok, Revision.t()} | {:error, term()}
  def fetch_revision(organization_id, mission_id, catalog_revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_revision_id) do
    case Repo.get_by(
           RevisionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           catalog_revision_id: catalog_revision_id
         ) do
      nil -> {:error, :catalog_revision_not_found}
      %RevisionRow{} = row -> {:ok, RevisionRow.to_domain(row)}
    end
  end

  @spec fetch_revision_by_import_run(binary(), binary(), binary()) ::
          {:ok, Revision.t()} | {:error, term()}
  def fetch_revision_by_import_run(organization_id, mission_id, import_run_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(import_run_id) do
    case Repo.get_by(
           RevisionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           import_run_id: import_run_id
         ) do
      nil -> {:error, :catalog_revision_not_found}
      %RevisionRow{} = row -> {:ok, RevisionRow.to_domain(row)}
    end
  end

  @spec list_revisions(binary(), binary(), binary() | nil, keyword()) :: [Revision.t()]
  def list_revisions(organization_id, mission_id, catalog_database_id \\ nil, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    RevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_catalog_database_id(catalog_database_id)
    |> maybe_filter_artifact_id(Keyword.get(opts, :artifact_id))
    |> maybe_filter_import_run_id(Keyword.get(opts, :import_run_id))
    |> order_by([row], desc: row.revision_number, desc: row.inserted_at)
    |> Repo.all()
    |> Enum.map(&RevisionRow.to_domain/1)
  end

  @spec latest_revision(binary(), binary(), binary()) :: {:ok, Revision.t()} | {:error, term()}
  def latest_revision(organization_id, mission_id, catalog_database_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_database_id) do
    RevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.catalog_database_id == ^catalog_database_id
    )
    |> order_by([row], desc: row.revision_number, desc: row.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :catalog_revision_not_found}
      %RevisionRow{} = row -> {:ok, RevisionRow.to_domain(row)}
    end
  end

  @spec latest_revision_by_database(binary(), binary()) :: %{optional(binary()) => Revision.t()}
  def latest_revision_by_database(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    RevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], desc: row.revision_number, desc: row.inserted_at)
    |> Repo.all()
    |> Enum.map(&RevisionRow.to_domain/1)
    |> Enum.reduce(%{}, fn %Revision{catalog_database_id: catalog_database_id} = revision, acc ->
      Map.put_new(acc, catalog_database_id, revision)
    end)
  end

  @spec start_revision_import(binary(), binary(), binary(), Artifact.t(), binary(), keyword()) ::
          {:ok, ImportRun.t()} | {:error, term()}
  def start_revision_import(
        organization_id,
        mission_id,
        catalog_database_id,
        %Artifact{} = artifact,
        importer_key,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_database_id) and is_binary(importer_key) and is_list(opts) do
    with {:ok, %Database{} = database} <-
           fetch_database(organization_id, mission_id, catalog_database_id),
         artifact <- %Artifact{artifact | catalog_database_id: catalog_database_id},
         :ok <-
           ensure_database_family_compatible(database.catalog_family, artifact.catalog_family),
         {:ok, %Artifact{} = persisted_artifact} <- persist_artifact(organization_id, artifact) do
      start_import_run(
        organization_id,
        mission_id,
        persisted_artifact.artifact_id,
        importer_key,
        opts
        |> Keyword.put(:catalog_database_id, catalog_database_id)
        |> Keyword.update(:metadata, %{"create_revision" => true}, fn
          metadata when is_map(metadata) -> Map.put(metadata, "create_revision", true)
          _other -> %{"create_revision" => true}
        end)
      )
    end
  end

  @spec recompile_telemetry_snapshot(binary(), binary(), binary(), keyword()) ::
          {:ok, RuntimeArtifacts.t()} | {:error, term()}
  def recompile_telemetry_snapshot(organization_id, mission_id, snapshot_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) and
             is_list(opts) do
    with {:ok, %TelemetryCatalogSnapshot{} = snapshot} <-
           fetch_telemetry_snapshot(organization_id, mission_id, snapshot_id),
         binding_set_version <-
           resolve_generated_runtime_version(organization_id, mission_id, snapshot) do
      {:ok,
       RuntimeArtifacts.compile(
         snapshot,
         Keyword.put(opts, :binding_set_version, binding_set_version)
       )}
    end
  end

  @spec diff_telemetry_snapshot_runtime(binary(), binary(), binary(), keyword()) ::
          {:ok, RuntimeDiff.report()} | {:error, term()}
  def diff_telemetry_snapshot_runtime(organization_id, mission_id, snapshot_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) and
             is_list(opts) do
    with {:ok, compilation} <-
           recompile_telemetry_snapshot(organization_id, mission_id, snapshot_id, opts) do
      existing_binding_set =
        case fetch_generated_runtime_binding_set(
               organization_id,
               mission_id,
               compilation.snapshot.import_run_id
             ) do
          {:ok, binding_set} -> binding_set
          {:error, :binding_set_not_found} -> nil
        end

      {:ok, RuntimeDiff.diff(compilation, existing_binding_set)}
    end
  end

  @spec materialize_telemetry_snapshot_runtime(binary(), binary(), binary(), keyword()) ::
          {:ok, RuntimeArtifacts.t()} | {:error, term()}
  def materialize_telemetry_snapshot_runtime(organization_id, mission_id, snapshot_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) and
             is_list(opts) do
    with {:ok, %TelemetryCatalogSnapshot{} = snapshot} <-
           fetch_telemetry_snapshot(organization_id, mission_id, snapshot_id),
         next_binding_set_version <-
           resolve_next_generated_runtime_version(organization_id, mission_id, snapshot),
         compilation <-
           RuntimeArtifacts.compile(
             snapshot,
             Keyword.put(opts, :binding_set_version, next_binding_set_version)
           ),
         {:ok, %{} = persisted_binding_set} <-
           Governance.persist_binding_set(organization_id, compilation.binding_set) do
      {:ok, %{compilation | binding_set: persisted_binding_set}}
    end
  end

  defp build_run(%Artifact{} = artifact, descriptor, opts) do
    ImportRun.new(%{
      organization_id: artifact.organization_id,
      mission_id: artifact.mission_id,
      catalog_database_id: artifact.catalog_database_id,
      artifact_id: artifact.artifact_id,
      catalog_family: artifact.catalog_family,
      importer_key: descriptor.importer_key,
      importer_version: descriptor.version,
      requested_by: Keyword.get(opts, :requested_by, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  defp maybe_attach_created_revision(%ImportRun{} = run) do
    if create_revision_run?(run) do
      case create_revision_from_completed_run(run) do
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
    else
      run
    end
  end

  defp create_revision_run?(%ImportRun{catalog_database_id: nil}), do: false

  defp create_revision_run?(%ImportRun{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "create_revision") == true or Map.get(metadata, :create_revision) == true
  end

  defp create_revision_run?(%ImportRun{}), do: false

  defp create_revision_from_completed_run(%ImportRun{} = run) do
    with {:ok, %Artifact{} = artifact} <-
           fetch_artifact(run.organization_id, run.mission_id, run.artifact_id),
         {:ok, %Database{} = database} <-
           fetch_database(run.organization_id, run.mission_id, run.catalog_database_id),
         telemetry_snapshot <- snapshot_id_for_run(TelemetrySnapshotRow, run.import_run_id),
         command_snapshot <- snapshot_id_for_run(CommandSnapshotRow, run.import_run_id),
         :ok <- ensure_revision_has_snapshot(telemetry_snapshot, command_snapshot),
         revision_number <- next_revision_number(run.catalog_database_id),
         revision_label <- revision_label(run, revision_number),
         revision <-
           Revision.new(%{
             organization_id: run.organization_id,
             mission_id: run.mission_id,
             catalog_database_id: run.catalog_database_id,
             revision_number: revision_number,
             revision_label: revision_label,
             catalog_family: database.catalog_family,
             artifact_id: artifact.artifact_id,
             import_run_id: run.import_run_id,
             telemetry_snapshot_id: telemetry_snapshot,
             command_snapshot_id: command_snapshot,
             content_sha256: artifact.content_sha256,
             created_by: run.requested_by,
             notes: metadata_value(run.metadata, "revision_notes"),
             metadata: %{
               "source_artifact_name" => artifact.artifact_name,
               "importer_key" => run.importer_key
             }
           }),
         {:ok, %RevisionRow{} = row} <-
           Repo.insert(RevisionRow.changeset(revision)),
         revision = RevisionRow.to_domain(row),
         {:ok, %OperationalEvent{}} <-
           revision
           |> OperationalEvent.from_catalog_revision(row.inserted_at)
           |> then(&OperationalEvents.persist_event(Repo, &1)) do
      maybe_invalidate_dashboard_catalog_revision(revision)
      {:ok, revision}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_invalidate_dashboard_catalog_revision(%Revision{} = revision) do
    config = Application.get_env(:cadence, :dashboard_runtime_invalidation, [])

    if Keyword.get(config, :enabled?, true) do
      RuntimeInvalidation.catalog_revision_changed(
        %{
          organization_id: revision.organization_id,
          mission_id: revision.mission_id
        },
        runtime_cache: Keyword.get(config, :runtime_cache, Cadence.Dashboards.RuntimeCache)
      )
    end

    :ok
  end

  defp snapshot_id_for_run(row_module, import_run_id) do
    case Repo.get_by(row_module, import_run_id: import_run_id) do
      %{snapshot_id: snapshot_id} -> snapshot_id
      nil -> nil
    end
  end

  defp ensure_revision_has_snapshot(nil, nil), do: {:error, :catalog_revision_requires_snapshot}
  defp ensure_revision_has_snapshot(_telemetry_snapshot_id, _command_snapshot_id), do: :ok

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

  defp metadata_atom_key("revision_label"), do: :revision_label
  defp metadata_atom_key("revision_notes"), do: :revision_notes
  defp metadata_atom_key(_key), do: nil

  defp execute_run(%ImportRun{} = run, %Artifact{} = artifact, importer_module) do
    context = %{
      organization_id: run.organization_id,
      mission_id: run.mission_id,
      import_run_id: run.import_run_id
    }

    case importer_module.import(source_from_artifact(artifact), context) do
      {:ok, %ImportResult{} = import_result} ->
        case ImportExecution.persist(
               run.organization_id,
               run.import_run_id,
               import_result
             ) do
          {:ok, outcome} ->
            completed_run =
              %ImportRun{
                run
                | snapshot_id: outcome.snapshot_id,
                  status: :completed,
                  imported_definition_count: outcome.imported_definition_count,
                  diagnostics: outcome.diagnostics,
                  result_document: outcome.result_document,
                  failure_reason: nil,
                  completed_at: DateTime.utc_now()
              }

            completed_run
            |> maybe_attach_created_revision()
            |> update_run()

          {:error, reason} ->
            fail_run(run, reason)
        end

      {:error, reason} ->
        fail_run(run, reason)
    end
  rescue
    exception ->
      failed_run =
        %ImportRun{
          run
          | status: :failed,
            failure_reason: {:exception, Exception.message(exception)},
            completed_at: DateTime.utc_now()
        }

      update_run(failed_run)
  catch
    kind, reason ->
      failed_run =
        %ImportRun{
          run
          | status: :failed,
            failure_reason: {kind, reason},
            completed_at: DateTime.utc_now()
        }

      update_run(failed_run)
  end

  defp fail_run(%ImportRun{} = run, reason) do
    failed_run = %ImportRun{
      run
      | status: :failed,
        failure_reason: reason,
        completed_at: DateTime.utc_now()
    }

    update_run(failed_run)
  end

  defp insert_run(%ImportRun{} = run) do
    case Repo.insert(ImportRunRow.changeset(run)) do
      {:ok, %ImportRunRow{} = row} ->
        domain_run = ImportRunRow.to_domain(row)
        Events.broadcast_started(domain_run)
        {:ok, domain_run}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_run(%ImportRun{} = run) do
    case Repo.get(ImportRunRow, run.import_run_id) do
      nil ->
        {:error, :catalog_import_run_not_found}

      %ImportRunRow{} = row ->
        case Repo.update(ImportRunRow.changeset(row, run)) do
          {:ok, %ImportRunRow{} = updated_row} ->
            domain_run = ImportRunRow.to_domain(updated_row)
            broadcast_for_status(domain_run)
            {:ok, domain_run}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp broadcast_for_status(%ImportRun{status: :completed} = run),
    do: Events.broadcast_completed(run)

  defp broadcast_for_status(%ImportRun{status: :failed} = run),
    do: Events.broadcast_failed(run)

  defp broadcast_for_status(%ImportRun{} = run),
    do: Events.broadcast_updated(run)

  defp fetch_import_run_by_id(import_run_id) do
    case Repo.get(ImportRunRow, import_run_id) do
      nil -> {:error, :catalog_import_run_not_found}
      %ImportRunRow{} = row -> {:ok, ImportRunRow.to_domain(row)}
    end
  end

  defp fetch_generated_runtime_binding_set(organization_id, mission_id, import_run_id)
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(import_run_id) do
    Governance.fetch_latest_binding_set(
      organization_id,
      mission_id,
      RuntimeArtifacts.binding_set_id(import_run_id)
    )
  end

  defp resolve_generated_runtime_version(organization_id, mission_id, snapshot)
       when is_binary(organization_id) and is_binary(mission_id) do
    case fetch_generated_runtime_binding_set(
           organization_id,
           mission_id,
           snapshot.import_run_id
         ) do
      {:ok, binding_set} -> binding_set.version
      {:error, :binding_set_not_found} -> 1
    end
  end

  defp resolve_next_generated_runtime_version(organization_id, mission_id, snapshot)
       when is_binary(organization_id) and is_binary(mission_id) do
    case fetch_generated_runtime_binding_set(
           organization_id,
           mission_id,
           snapshot.import_run_id
         ) do
      {:ok, binding_set} -> binding_set.version + 1
      {:error, :binding_set_not_found} -> 1
    end
  end

  defp put_telemetry_snapshot_organization_scope(
         %TelemetryCatalogSnapshot{} = snapshot,
         organization_id
       )
       when is_binary(organization_id) and organization_id != "" do
    case snapshot.organization_id do
      nil ->
        {:ok, %TelemetryCatalogSnapshot{snapshot | organization_id: organization_id}}

      ^organization_id ->
        {:ok, snapshot}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          snapshot.mission_id}}
    end
  end

  defp put_command_snapshot_organization_scope(
         %CommandCatalogSnapshot{} = snapshot,
         organization_id
       )
       when is_binary(organization_id) and organization_id != "" do
    case snapshot.organization_id do
      nil ->
        {:ok, %CommandCatalogSnapshot{snapshot | organization_id: organization_id}}

      ^organization_id ->
        {:ok, snapshot}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          snapshot.mission_id}}
    end
  end

  defp put_organization_scope(%Artifact{} = artifact, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case artifact.organization_id do
      nil ->
        {:ok, %Artifact{artifact | organization_id: organization_id}}

      ^organization_id ->
        {:ok, artifact}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          artifact.mission_id}}
    end
  end

  defp ensure_catalog_family_match(catalog_family, catalog_family), do: :ok

  defp ensure_catalog_family_match(artifact_catalog_family, importer_catalog_family) do
    {:error,
     {:catalog_importer_family_mismatch, artifact_catalog_family, importer_catalog_family}}
  end

  defp ensure_database_family_compatible(:combined, catalog_family)
       when catalog_family in [:telemetry, :command, :combined],
       do: :ok

  defp ensure_database_family_compatible(catalog_family, catalog_family), do: :ok

  defp ensure_database_family_compatible(database_catalog_family, artifact_catalog_family) do
    {:error,
     {:catalog_database_family_mismatch, database_catalog_family, artifact_catalog_family}}
  end

  defp ensure_database_scope(_organization_id, _mission_id, nil), do: :ok

  defp ensure_database_scope(organization_id, mission_id, catalog_database_id)
       when is_binary(catalog_database_id) do
    case fetch_database(organization_id, mission_id, catalog_database_id) do
      {:ok, %Database{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_artifact(importer_module, %Artifact{} = artifact) do
    if function_exported?(importer_module, :validate, 1) do
      importer_module.validate(source_from_artifact(artifact))
    else
      :ok
    end
  end

  defp source_from_artifact(%Artifact{} = artifact) do
    Source.new(%{
      artifact_id: artifact.artifact_id,
      organization_id: artifact.organization_id,
      mission_id: artifact.mission_id,
      catalog_family: artifact.catalog_family,
      artifact_name: artifact.artifact_name,
      format_key: artifact.format_key,
      format_version: artifact.format_version,
      media_type: artifact.media_type,
      source_artifact: artifact.source_artifact,
      metadata: artifact.metadata
    })
  end

  defp maybe_filter_catalog_family(query, nil), do: query

  defp maybe_filter_catalog_family(query, catalog_family) do
    where(query, [row], row.catalog_family == ^Atom.to_string(catalog_family))
  end

  defp maybe_filter_catalog_database_id(query, nil), do: query

  defp maybe_filter_catalog_database_id(query, catalog_database_id),
    do: where(query, [row], row.catalog_database_id == ^catalog_database_id)

  defp maybe_filter_artifact_id(query, nil), do: query

  defp maybe_filter_artifact_id(query, artifact_id),
    do: where(query, [row], row.artifact_id == ^artifact_id)

  defp maybe_filter_import_run_id(query, nil), do: query

  defp maybe_filter_import_run_id(query, import_run_id),
    do: where(query, [row], row.import_run_id == ^import_run_id)

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status),
    do: where(query, [row], row.status == ^Atom.to_string(status))
end
