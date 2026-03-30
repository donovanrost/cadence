defmodule Cadence.Catalog do
  @moduledoc """
  Shared catalog artifact and import-run infrastructure for telemetry and command
  catalog import.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Cadence.Catalog.{Artifact, ImportResult, ImportRun, Registry}
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias Cadence.Catalog.Telemetry.{RuntimeArtifacts, RuntimeDiff}
  alias Cadence.Governance
  alias Cadence.Missions
  alias Cadence.Jobs

  alias Cadence.Persistence.Schemas.{
    CatalogArtifactRow,
    CatalogCommandSnapshotRow,
    CatalogImportRunRow,
    CatalogTelemetrySnapshotRow
  }

  alias Cadence.Repo

  @spec list_importers(keyword()) :: [%{module: module(), descriptor: map()}]
  def list_importers(opts \\ []) when is_list(opts) do
    Registry.list_importers(opts)
  end

  @spec persist_artifact(binary(), Artifact.t()) :: {:ok, Artifact.t()} | {:error, term()}
  def persist_artifact(organization_id, %Artifact{} = artifact) when is_binary(organization_id) do
    with {:ok, scoped_artifact} <- put_organization_scope(artifact, organization_id),
         {:ok, _mission} <- Missions.fetch_mission(organization_id, scoped_artifact.mission_id),
         {:ok, _row} <-
           Repo.insert(CatalogArtifactRow.changeset(scoped_artifact),
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
           CatalogArtifactRow,
           organization_id: organization_id,
           mission_id: mission_id,
           artifact_id: artifact_id
         ) do
      nil -> {:error, :catalog_artifact_not_found}
      %CatalogArtifactRow{} = row -> {:ok, CatalogArtifactRow.to_domain(row)}
    end
  end

  @spec list_artifacts(binary(), binary(), keyword()) :: [Artifact.t()]
  def list_artifacts(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    catalog_family = Keyword.get(opts, :catalog_family)

    CatalogArtifactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_catalog_family(catalog_family)
    |> order_by([row], desc: row.uploaded_at, desc: row.artifact_id)
    |> Repo.all()
    |> Enum.map(&CatalogArtifactRow.to_domain/1)
  end

  @spec start_import_run(binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, ImportRun.t()} | {:error, term()}
  def start_import_run(organization_id, mission_id, artifact_id, importer_key, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(artifact_id) and
             is_binary(importer_key) and is_list(opts) do
    with {:ok, %Artifact{} = artifact} <- fetch_artifact(organization_id, mission_id, artifact_id),
         {:ok, %{module: importer_module, descriptor: descriptor}} <-
           Registry.fetch_importer(importer_key),
         :ok <- ensure_catalog_family_match(artifact.catalog_family, descriptor.catalog_family),
         :ok <- validate_artifact(importer_module, artifact),
         run <- build_run(artifact, importer_key, opts),
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
           Registry.fetch_importer(run.importer_key),
         :ok <- ensure_catalog_family_match(artifact.catalog_family, descriptor.catalog_family),
         :ok <- validate_artifact(importer_module, artifact) do
      execute_run(run, artifact, importer_module)
    end
  end

  @spec fetch_import_run(binary(), binary(), binary()) :: {:ok, ImportRun.t()} | {:error, term()}
  def fetch_import_run(organization_id, mission_id, import_run_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(import_run_id) do
    case Repo.get_by(
           CatalogImportRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           import_run_id: import_run_id
         ) do
      nil -> {:error, :catalog_import_run_not_found}
      %CatalogImportRunRow{} = row -> {:ok, CatalogImportRunRow.to_domain(row)}
    end
  end

  @spec list_import_runs(binary(), binary(), keyword()) :: [ImportRun.t()]
  def list_import_runs(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    artifact_id = Keyword.get(opts, :artifact_id)
    status = Keyword.get(opts, :status)

    CatalogImportRunRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_artifact_id(artifact_id)
    |> maybe_filter_status(status)
    |> order_by([row], desc: row.started_at, desc: row.import_run_id)
    |> Repo.all()
    |> Enum.map(&CatalogImportRunRow.to_domain/1)
  end

  @spec persist_telemetry_snapshot(binary(), TelemetryCatalogSnapshot.t()) ::
          {:ok, TelemetryCatalogSnapshot.t()} | {:error, term()}
  def persist_telemetry_snapshot(organization_id, %TelemetryCatalogSnapshot{} = snapshot)
      when is_binary(organization_id) do
    with {:ok, scoped_snapshot} <-
           put_telemetry_snapshot_organization_scope(snapshot, organization_id),
         {:ok, _mission} <- Missions.fetch_mission(organization_id, scoped_snapshot.mission_id),
         {:ok, _row} <-
           Repo.insert(CatalogTelemetrySnapshotRow.changeset(scoped_snapshot),
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
           Repo.insert(CatalogCommandSnapshotRow.changeset(scoped_snapshot),
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
           CatalogTelemetrySnapshotRow,
           organization_id: organization_id,
           mission_id: mission_id,
           snapshot_id: snapshot_id
         ) do
      nil -> {:error, :catalog_telemetry_snapshot_not_found}
      %CatalogTelemetrySnapshotRow{} = row -> {:ok, CatalogTelemetrySnapshotRow.to_domain(row)}
    end
  end

  @spec list_telemetry_snapshots(binary(), binary(), keyword()) :: [TelemetryCatalogSnapshot.t()]
  def list_telemetry_snapshots(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    artifact_id = Keyword.get(opts, :artifact_id)
    import_run_id = Keyword.get(opts, :import_run_id)

    CatalogTelemetrySnapshotRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_artifact_id(artifact_id)
    |> maybe_filter_import_run_id(import_run_id)
    |> order_by([row], desc: row.inserted_at, desc: row.snapshot_id)
    |> Repo.all()
    |> Enum.map(&CatalogTelemetrySnapshotRow.to_domain/1)
  end

  @spec fetch_command_snapshot(binary(), binary(), binary()) ::
          {:ok, CommandCatalogSnapshot.t()} | {:error, term()}
  def fetch_command_snapshot(organization_id, mission_id, snapshot_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(snapshot_id) do
    case Repo.get_by(
           CatalogCommandSnapshotRow,
           organization_id: organization_id,
           mission_id: mission_id,
           snapshot_id: snapshot_id
         ) do
      nil -> {:error, :catalog_command_snapshot_not_found}
      %CatalogCommandSnapshotRow{} = row -> {:ok, CatalogCommandSnapshotRow.to_domain(row)}
    end
  end

  @spec list_command_snapshots(binary(), binary(), keyword()) :: [CommandCatalogSnapshot.t()]
  def list_command_snapshots(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    artifact_id = Keyword.get(opts, :artifact_id)
    import_run_id = Keyword.get(opts, :import_run_id)

    CatalogCommandSnapshotRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_artifact_id(artifact_id)
    |> maybe_filter_import_run_id(import_run_id)
    |> order_by([row], desc: row.inserted_at, desc: row.snapshot_id)
    |> Repo.all()
    |> Enum.map(&CatalogCommandSnapshotRow.to_domain/1)
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

  defp build_run(%Artifact{} = artifact, importer_key, opts) do
    ImportRun.new(%{
      organization_id: artifact.organization_id,
      mission_id: artifact.mission_id,
      artifact_id: artifact.artifact_id,
      catalog_family: artifact.catalog_family,
      importer_key: importer_key,
      requested_by: Keyword.get(opts, :requested_by, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  defp execute_run(%ImportRun{} = run, %Artifact{} = artifact, importer_module) do
    context = %{
      organization_id: run.organization_id,
      mission_id: run.mission_id,
      import_run_id: run.import_run_id
    }

    case importer_module.import(artifact, context) do
      {:ok, %ImportResult{} = import_result} ->
        completed_run =
          %ImportRun{
            run
            | snapshot_id: import_result.snapshot_id,
              status: :completed,
              imported_definition_count: import_result.imported_definition_count,
              diagnostics: import_result.diagnostics,
              result_document: import_result.result_document,
              failure_reason: nil,
              completed_at: DateTime.utc_now()
          }

        update_run(completed_run)

      {:error, reason} ->
        failed_run =
          %ImportRun{
            run
            | status: :failed,
              failure_reason: reason,
              completed_at: DateTime.utc_now()
          }

        update_run(failed_run)
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

  defp insert_run(%ImportRun{} = run) do
    case Repo.insert(CatalogImportRunRow.changeset(run)) do
      {:ok, %CatalogImportRunRow{} = row} -> {:ok, CatalogImportRunRow.to_domain(row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_run(%ImportRun{} = run) do
    case Repo.get(CatalogImportRunRow, run.import_run_id) do
      nil ->
        {:error, :catalog_import_run_not_found}

      %CatalogImportRunRow{} = row ->
        case Repo.update(CatalogImportRunRow.changeset(row, run)) do
          {:ok, %CatalogImportRunRow{} = updated_row} ->
            {:ok, CatalogImportRunRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_import_run_by_id(import_run_id) do
    case Repo.get(CatalogImportRunRow, import_run_id) do
      nil -> {:error, :catalog_import_run_not_found}
      %CatalogImportRunRow{} = row -> {:ok, CatalogImportRunRow.to_domain(row)}
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

  defp validate_artifact(importer_module, %Artifact{} = artifact) do
    if function_exported?(importer_module, :validate_artifact, 1) do
      importer_module.validate_artifact(artifact)
    else
      :ok
    end
  end

  defp maybe_filter_catalog_family(query, nil), do: query

  defp maybe_filter_catalog_family(query, catalog_family) do
    where(query, [row], row.catalog_family == ^Atom.to_string(catalog_family))
  end

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
