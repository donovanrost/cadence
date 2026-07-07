defmodule Cadence.Dashboards.DocumentStore do
  @moduledoc """
  Persistence boundary for canonical dashboard engine documents.

  This store uses the existing `ops_dashboards` table while moving new dashboard
  writes to `Cadence.Dashboards.Document` as the persisted artifact.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DashboardSummary,
    Document,
    DocumentMigration,
    LifecycleEvent,
    RuntimeInvalidation,
    Version
  }

  alias Cadence.Missions
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Persistence.Schemas.{
    DashboardLifecycleEventRow,
    DashboardVersionRow,
    OpsDashboardRow
  }

  alias Cadence.Repo

  @spec persist_document(binary(), Document.t()) :: {:ok, Document.t()} | {:error, term()}
  def persist_document(organization_id, %Document{} = document) when is_binary(organization_id) do
    with {:ok, scoped_document} <- put_organization_scope(document, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_document.organization_id, scoped_document.mission_id),
         :ok <- validate_document(scoped_document),
         versioned_document <- ensure_initial_version(scoped_document),
         {:ok, document} <- insert_document_with_version(versioned_document) do
      invalidate_dashboard_runtime(document, :created)
      {:ok, document}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_document(binary(), binary(), binary(), Document.t(), keyword()) ::
          {:ok, Document.t()} | {:error, term()}
  def update_document(
        organization_id,
        mission_id,
        dashboard_id,
        %Document{} = document,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    expected_version = Keyword.get(opts, :expected_version, Document.version(document))

    with %OpsDashboardRow{} = row <- get_row(organization_id, mission_id, dashboard_id),
         :ok <- reject_archived(row),
         {:ok, scoped_document} <-
           put_path_scope(document, organization_id, mission_id, dashboard_id),
         :ok <- validate_document(scoped_document),
         :ok <- check_expected_version(row, expected_version),
         versioned_document <- put_next_version(scoped_document, row),
         {:ok, document} <-
           update_document_with_version(
             row,
             versioned_document,
             organization_id,
             mission_id,
             dashboard_id,
             opts
           ) do
      invalidate_dashboard_runtime(document, :draft_saved)
      {:ok, document}
    else
      nil -> {:error, :dashboard_not_found}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_document(binary(), binary(), binary()) ::
          {:ok, Document.t()} | {:error, :dashboard_not_found}
  def fetch_document(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil -> {:error, :dashboard_not_found}
      %OpsDashboardRow{} = row -> fetch_or_migrate_row_document(row)
    end
  end

  @spec fetch_published_document(binary(), binary(), binary()) ::
          {:ok, Document.t()}
          | {:error,
             :dashboard_not_found
             | :dashboard_archived
             | :dashboard_not_published
             | :dashboard_version_not_found}
  def fetch_published_document(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row when row.lifecycle_state == "archived" ->
        {:error, :dashboard_archived}

      %OpsDashboardRow{} = row ->
        fetch_published_document(row, organization_id, mission_id, dashboard_id)
    end
  end

  @spec fetch_document_for_mode(
          binary(),
          binary(),
          binary(),
          :view | :published | :edit | :draft | :latest
        ) ::
          {:ok, Document.t()}
          | {:error,
             :dashboard_not_found
             | :dashboard_archived
             | :dashboard_not_published
             | :dashboard_version_not_found}
  def fetch_document_for_mode(organization_id, mission_id, dashboard_id, mode)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    case mode do
      mode when mode in [:view, :published] ->
        fetch_published_document(organization_id, mission_id, dashboard_id)

      mode when mode in [:edit, :draft, :latest] ->
        fetch_active_document(organization_id, mission_id, dashboard_id)
    end
  end

  @spec list_documents(binary(), binary()) :: [Document.t()]
  def list_documents(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    organization_id
    |> list_rows(mission_id, "active")
    |> Enum.map(&OpsDashboardRow.to_document/1)
  end

  @spec list_dashboard_summaries(binary(), binary()) :: [DashboardSummary.t()]
  def list_dashboard_summaries(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    organization_id
    |> list_rows(mission_id, "active")
    |> Enum.map(&summary_from_row/1)
  end

  @spec list_archived_dashboard_summaries(binary(), binary()) :: [DashboardSummary.t()]
  def list_archived_dashboard_summaries(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    organization_id
    |> list_rows(mission_id, "archived")
    |> Enum.map(&summary_from_row/1)
  end

  @spec archive_document(binary(), binary(), binary(), keyword()) ::
          :ok | {:error, :dashboard_not_found | Changeset.t() | term()}
  def archive_document(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    set_lifecycle_state(organization_id, mission_id, dashboard_id, "archived", opts)
  end

  @spec restore_document(binary(), binary(), binary(), keyword()) ::
          :ok | {:error, :dashboard_not_found | Changeset.t() | term()}
  def restore_document(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    set_lifecycle_state(organization_id, mission_id, dashboard_id, "active", opts)
  end

  defp summary_from_row(%OpsDashboardRow{} = row) do
    row
    |> OpsDashboardRow.to_document()
    |> DashboardSummary.from_document(row)
  end

  defp fetch_active_document(organization_id, mission_id, dashboard_id) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row when row.lifecycle_state == "archived" ->
        {:error, :dashboard_archived}

      %OpsDashboardRow{} = row ->
        fetch_or_migrate_row_document(row)
    end
  end

  defp fetch_or_migrate_row_document(%OpsDashboardRow{} = row) do
    with {:ok, %DocumentMigration.Result{} = result} <-
           row
           |> row_document_map()
           |> DocumentMigration.migrate_map() do
      if result.changed? do
        migrate_row_document(row, result)
      else
        {:ok, result.document}
      end
    end
  end

  defp row_document_map(%OpsDashboardRow{} = row) do
    document =
      case row.document do
        document when is_map(document) and document != %{} ->
          document

        _missing ->
          %{}
      end

    document
    |> put_missing_attr("dashboard_id", row.dashboard_id)
    |> put_missing_attr("organization_id", row.organization_id)
    |> put_missing_attr("mission_id", row.mission_id)
    |> put_missing_attr("name", row.name)
    |> put_missing_attr("description", row.description)
  end

  defp put_missing_attr(attrs, _key, nil), do: attrs

  defp put_missing_attr(attrs, key, value) when is_map(attrs) do
    if document_attr_present?(attrs, key) do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  defp document_attr_present?(attrs, "dashboard_id"),
    do: Map.has_key?(attrs, "dashboard_id") or Map.has_key?(attrs, :dashboard_id)

  defp document_attr_present?(attrs, "organization_id"),
    do: Map.has_key?(attrs, "organization_id") or Map.has_key?(attrs, :organization_id)

  defp document_attr_present?(attrs, "mission_id"),
    do: Map.has_key?(attrs, "mission_id") or Map.has_key?(attrs, :mission_id)

  defp document_attr_present?(attrs, "name"),
    do: Map.has_key?(attrs, "name") or Map.has_key?(attrs, :name)

  defp document_attr_present?(attrs, "description"),
    do: Map.has_key?(attrs, "description") or Map.has_key?(attrs, :description)

  defp set_lifecycle_state(organization_id, mission_id, dashboard_id, lifecycle_state, opts) do
    organization_id
    |> get_row(mission_id, dashboard_id)
    |> set_lifecycle_state(lifecycle_state, opts)
  end

  defp set_lifecycle_state(nil, _lifecycle_state, _opts), do: {:error, :dashboard_not_found}

  defp set_lifecycle_state(%OpsDashboardRow{} = row, lifecycle_state, opts) do
    event_type = lifecycle_event_type(lifecycle_state)
    occurred_at = event_time(opts)

    with :ok <- check_expected_version(row, Keyword.get(opts, :expected_version)) do
      row
      |> update_lifecycle_state_with_event(lifecycle_state, event_type, occurred_at, opts)
      |> handle_lifecycle_update_result(event_type)
    end
  end

  defp update_lifecycle_state_with_event(row, lifecycle_state, event_type, occurred_at, opts) do
    Repo.transaction(fn ->
      with {:ok, %OpsDashboardRow{} = updated_row} <-
             update_lifecycle_row(row, lifecycle_state),
           {:ok, %LifecycleEvent{}} <-
             insert_lifecycle_event(row, updated_row, event_type, occurred_at, opts) do
        updated_row
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp handle_lifecycle_update_result({:ok, %OpsDashboardRow{} = updated_row}, event_type) do
    updated_row
    |> OpsDashboardRow.to_document()
    |> invalidate_dashboard_runtime(event_type)

    :ok
  end

  defp handle_lifecycle_update_result({:error, %Changeset{} = changeset}, _event_type) do
    {:error, changeset}
  end

  defp handle_lifecycle_update_result({:error, reason}, _event_type), do: {:error, reason}

  defp list_rows(organization_id, mission_id, lifecycle_state) do
    OpsDashboardRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.lifecycle_state == ^lifecycle_state
    )
    |> order_by([row], asc: row.name)
    |> Repo.all()
  end

  @spec delete_document(binary(), binary(), binary(), keyword()) ::
          :ok | {:error, :dashboard_not_found | term()}
  def delete_document(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row ->
        with :ok <- check_expected_version(row, Keyword.get(opts, :expected_version)),
             :ok <- delete_row(row, organization_id, mission_id, dashboard_id) do
          row
          |> OpsDashboardRow.to_document()
          |> invalidate_dashboard_runtime(:deleted)

          :ok
        end
    end
  end

  @spec list_versions(binary(), binary(), binary()) :: [Version.t()]
  def list_versions(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DashboardVersionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_id == ^dashboard_id
    )
    |> order_by([row], asc: row.version)
    |> Repo.all()
    |> Enum.map(&DashboardVersionRow.to_domain/1)
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, Version.t()} | {:error, :dashboard_version_not_found}
  def fetch_version(organization_id, mission_id, dashboard_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_integer(version) and version > 0 do
    case Repo.get_by(DashboardVersionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           dashboard_id: dashboard_id,
           version: version
         ) do
      nil -> {:error, :dashboard_version_not_found}
      %DashboardVersionRow{} = row -> {:ok, DashboardVersionRow.to_domain(row)}
    end
  end

  @spec publish_document(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Version.t()} | {:error, term()}
  def publish_document(organization_id, mission_id, dashboard_id, version, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_integer(version) and version > 0 do
    with %OpsDashboardRow{} = row <- get_row(organization_id, mission_id, dashboard_id),
         :ok <- reject_archived(row),
         :ok <- check_expected_version(row, Keyword.get(opts, :expected_version)),
         {:ok, %Version{} = snapshot} <-
           fetch_version(organization_id, mission_id, dashboard_id, version),
         :ok <- validate_publish_readiness(organization_id, mission_id, snapshot.document),
         {:ok, %Version{} = published_snapshot} <-
           publish_row_with_event(
             row,
             snapshot,
             organization_id,
             mission_id,
             dashboard_id,
             opts
           ) do
      invalidate_dashboard_runtime(published_snapshot.document, :published)
      {:ok, published_snapshot}
    else
      nil -> {:error, :dashboard_not_found}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec revert_document(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, Version.t()} | {:error, term()}
  def revert_document(organization_id, mission_id, dashboard_id, version, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_integer(version) and version > 0 do
    with %OpsDashboardRow{} = row <- get_row(organization_id, mission_id, dashboard_id),
         :ok <- reject_archived(row),
         :ok <- check_expected_version(row, Keyword.get(opts, :expected_version)),
         {:ok, %Version{} = source_version} <-
           fetch_version(organization_id, mission_id, dashboard_id, version),
         %Document{} = reverted_document <- reverted_document(source_version.document, row),
         :ok <- validate_document(reverted_document),
         {:ok, %Version{} = reverted_version} <-
           revert_row_with_version(
             row,
             reverted_document,
             source_version,
             organization_id,
             mission_id,
             dashboard_id,
             opts
           ) do
      invalidate_dashboard_runtime(reverted_version.document, :reverted,
        source_version: source_version.version
      )

      {:ok, reverted_version}
    else
      nil -> {:error, :dashboard_not_found}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject_archived(%OpsDashboardRow{} = row) do
    if OpsDashboardRow.archived?(row), do: {:error, :dashboard_archived}, else: :ok
  end

  defp get_row(organization_id, mission_id, dashboard_id) do
    Repo.get_by(OpsDashboardRow,
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id
    )
  end

  defp get_row_for_update(organization_id, mission_id, dashboard_id) do
    OpsDashboardRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_id == ^dashboard_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp unwrap_transaction_result({:ok, result}), do: result
  defp unwrap_transaction_result({:error, reason}), do: {:error, reason}

  defp fetch_published_document(
         %OpsDashboardRow{} = row,
         organization_id,
         mission_id,
         dashboard_id
       ) do
    case OpsDashboardRow.published_version(row) do
      nil ->
        {:error, :dashboard_not_published}

      version ->
        with {:ok, %Version{} = snapshot} <-
               fetch_version(organization_id, mission_id, dashboard_id, version) do
          {:ok, snapshot.document}
        end
    end
  end

  defp put_organization_scope(%Document{} = document, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case document.organization_id do
      nil ->
        {:ok, %Document{document | organization_id: organization_id}}

      ^organization_id ->
        {:ok, document}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          document.mission_id}}
    end
  end

  defp put_path_scope(%Document{} = document, organization_id, mission_id, dashboard_id) do
    cond do
      document.organization_id not in [nil, organization_id] ->
        {:error,
         {:organization_mission_mismatch, document.organization_id, organization_id, mission_id}}

      document.mission_id != mission_id ->
        {:error, {:mission_mismatch, document.mission_id, mission_id}}

      document.dashboard_id != dashboard_id ->
        {:error, {:dashboard_mismatch, document.dashboard_id, dashboard_id}}

      true ->
        {:ok, %Document{document | organization_id: organization_id}}
    end
  end

  defp validate_document(%Document{} = document) do
    case Dashboards.validate_document(document) do
      %{valid?: true} -> :ok
      result -> {:error, {:invalid_dashboard_document, result}}
    end
  end

  defp validate_publish_readiness(organization_id, mission_id, %Document{} = document) do
    case Dashboards.validate_publish_readiness(organization_id, mission_id, document) do
      %{valid?: true} -> :ok
      result -> {:error, {:invalid_dashboard_document, result}}
    end
  end

  defp ensure_initial_version(%Document{} = document) do
    case Document.version(document) do
      version when is_integer(version) and version > 0 -> document
      _missing -> Document.put_version(document, 1)
    end
  end

  defp put_next_version(%Document{} = document, %OpsDashboardRow{} = row) do
    current_version =
      [
        OpsDashboardRow.latest_version(row),
        OpsDashboardRow.document_version(row),
        Document.version(document),
        0
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.max()

    next_version = current_version + 1
    Document.put_version(document, next_version)
  end

  defp reverted_document(%Document{} = document, %OpsDashboardRow{} = row) do
    Document.put_version(document, next_dashboard_version(row))
  end

  defp next_dashboard_version(%OpsDashboardRow{} = row) do
    [
      OpsDashboardRow.latest_version(row),
      OpsDashboardRow.document_version(row),
      0
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.max()
    |> Kernel.+(1)
  end

  defp insert_document_with_version(%Document{} = versioned_document) do
    Repo.transaction(fn ->
      with {:ok, %OpsDashboardRow{} = row} <-
             Repo.insert(OpsDashboardRow.document_changeset(versioned_document)),
           {:ok, %Version{}} <- insert_version(versioned_document) do
        OpsDashboardRow.to_document(row)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp update_document_with_version(
         %OpsDashboardRow{} = row,
         %Document{} = versioned_document,
         organization_id,
         mission_id,
         dashboard_id,
         opts
       ) do
    parent_version = OpsDashboardRow.latest_version(row)

    Repo.transaction(fn ->
      with {:ok, %OpsDashboardRow{} = updated_row} <-
             update_row(row, versioned_document, organization_id, mission_id, dashboard_id),
           {:ok, %Version{}} <-
             insert_version(
               versioned_document,
               Keyword.merge(snapshot_opts(opts),
                 parent_version: parent_version,
                 based_on_version: Keyword.get(opts, :expected_version, parent_version)
               )
             ) do
        OpsDashboardRow.to_document(updated_row)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp migrate_row_document(
         %OpsDashboardRow{} = row,
         %DocumentMigration.Result{} = migration_result
       ) do
    versioned_document =
      Document.put_version(migration_result.document, next_dashboard_version(row))

    parent_version = OpsDashboardRow.latest_version(row)

    opts = [
      snapshot_kind: :migration,
      change_summary: migration_change_summary(migration_result),
      expected_version: parent_version
    ]

    with :ok <- validate_document(versioned_document),
         {:ok, %Document{} = document} <-
           update_document_with_version(
             row,
             versioned_document,
             row.organization_id,
             row.mission_id,
             row.dashboard_id,
             opts
           ) do
      invalidate_dashboard_runtime(document, :migrated)
      {:ok, document}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp revert_row_with_version(
         %OpsDashboardRow{} = row,
         %Document{} = reverted_document,
         %Version{} = source_version,
         organization_id,
         mission_id,
         dashboard_id,
         opts
       ) do
    parent_version = OpsDashboardRow.latest_version(row)
    occurred_at = event_time(opts)

    Repo.transaction(fn ->
      with {:ok, %OpsDashboardRow{} = updated_row} <-
             update_row(row, reverted_document, organization_id, mission_id, dashboard_id),
           {:ok, %Version{} = version} <-
             insert_version(
               reverted_document,
               Keyword.merge(snapshot_opts(opts),
                 snapshot_kind: :revert,
                 parent_version: parent_version,
                 based_on_version: source_version.version,
                 change_summary: revert_change_summary(source_version, opts)
               )
             ),
           {:ok, %LifecycleEvent{}} <-
             insert_lifecycle_event(
               row,
               updated_row,
               :reverted,
               occurred_at,
               Keyword.merge(opts,
                 actor_id: Keyword.get(opts, :actor_id, Keyword.get(opts, :created_by)),
                 payload: %{
                   "source_version" => source_version.version,
                   "reverted_version" => version.version
                 }
               )
             ) do
        version
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_version(%Document{} = document, opts \\ []) do
    version = %Version{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      version: Document.version(document),
      document: document,
      snapshot_kind: Keyword.get(opts, :snapshot_kind, :draft_save),
      parent_version: Keyword.get(opts, :parent_version),
      based_on_version: Keyword.get(opts, :based_on_version),
      change_summary: Keyword.get(opts, :change_summary),
      created_by: Keyword.get(opts, :created_by),
      schema_version: document.schema_version
    }

    version
    |> DashboardVersionRow.changeset()
    |> Repo.insert()
    |> case do
      {:ok, %DashboardVersionRow{} = row} -> {:ok, DashboardVersionRow.to_domain(row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp snapshot_opts(opts) do
    Keyword.take(opts, [:snapshot_kind, :change_summary, :created_by])
  end

  defp migration_change_summary(%DocumentMigration.Result{} = result) do
    "Migrated dashboard document from schema v#{result.source_schema_version} to v#{result.target_schema_version}: " <>
      Enum.join(result.migrations, ", ")
  end

  defp revert_change_summary(%Version{} = source_version, opts) do
    Keyword.get(opts, :change_summary, "Restored version #{source_version.version} as draft")
  end

  defp check_expected_version(_row, nil), do: :ok

  defp check_expected_version(%OpsDashboardRow{} = row, expected_version)
       when is_integer(expected_version) and expected_version > 0 do
    current_version = OpsDashboardRow.latest_version(row)

    if current_version == expected_version do
      :ok
    else
      {:error, {:dashboard_version_conflict, current_version}}
    end
  end

  defp check_expected_version(%OpsDashboardRow{} = row, _expected_version) do
    {:error, {:dashboard_version_conflict, OpsDashboardRow.latest_version(row)}}
  end

  defp update_row(row, versioned_document, organization_id, mission_id, dashboard_id) do
    row
    |> OpsDashboardRow.document_changeset(versioned_document)
    |> Changeset.optimistic_lock(:lock_version)
    |> Repo.update(stale_error_field: :lock_version)
    |> case do
      {:ok, %OpsDashboardRow{} = updated_row} ->
        {:ok, updated_row}

      {:error, %Changeset{} = changeset} ->
        if stale_lock_error?(changeset) do
          {:error,
           {:dashboard_version_conflict,
            current_document_version(organization_id, mission_id, dashboard_id)}}
        else
          {:error, changeset}
        end
    end
  end

  @spec list_lifecycle_events(binary(), binary(), binary()) :: [LifecycleEvent.t()]
  def list_lifecycle_events(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    DashboardLifecycleEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_id == ^dashboard_id
    )
    |> order_by([row], asc: row.occurred_at, asc: row.dashboard_lifecycle_event_id)
    |> Repo.all()
    |> Enum.map(&DashboardLifecycleEventRow.to_domain/1)
  end

  @spec fetch_lifecycle_event(binary(), binary(), binary()) ::
          {:ok, LifecycleEvent.t()} | {:error, :not_found}
  def fetch_lifecycle_event(organization_id, mission_id, dashboard_lifecycle_event_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(dashboard_lifecycle_event_id) do
    DashboardLifecycleEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_lifecycle_event_id == ^dashboard_lifecycle_event_id
    )
    |> Repo.one()
    |> case do
      %DashboardLifecycleEventRow{} = row -> {:ok, DashboardLifecycleEventRow.to_domain(row)}
      nil -> {:error, :not_found}
    end
  end

  @spec list_open_comparison_review_requests(binary(), binary(), binary()) :: [LifecycleEvent.t()]
  def list_open_comparison_review_requests(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    events = list_comparison_review_events(organization_id, mission_id, dashboard_id)

    ComparisonReviewQueue.open_requests(events)
  end

  @spec comparison_review_queue(binary(), binary(), binary()) ::
          ComparisonReviewQueue.open_summary()
  def comparison_review_queue(organization_id, mission_id, dashboard_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) do
    organization_id
    |> list_comparison_review_events(mission_id, dashboard_id)
    |> ComparisonReviewQueue.open_summary()
  end

  @spec record_comparison_review_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_comparison_review_request(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    transaction_with_dashboard_lock(organization_id, mission_id, dashboard_id, fn row ->
      record_comparison_review_request_for_row(
        row,
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts
      )
    end)
  end

  defp record_comparison_review_request_for_row(
         %OpsDashboardRow{} = row,
         organization_id,
         mission_id,
         dashboard_id,
         payload,
         opts
       ) do
    with :ok <- reject_archived(row),
         :ok <-
           reject_existing_open_comparison_review_request(
             organization_id,
             mission_id,
             dashboard_id,
             payload
           ) do
      insert_lifecycle_event(
        row,
        row,
        :comparison_review_requested,
        event_time(opts),
        Keyword.merge(opts, payload: comparison_review_request_payload(row, payload))
      )
    end
  end

  defp transaction_with_dashboard_lock(organization_id, mission_id, dashboard_id, fun)
       when is_function(fun, 1) do
    Repo.transaction(fn ->
      organization_id
      |> get_row_for_update(mission_id, dashboard_id)
      |> case do
        nil -> {:error, :dashboard_not_found}
        %OpsDashboardRow{} = row -> fun.(row)
      end
    end)
    |> unwrap_transaction_result()
  end

  @spec record_comparison_review_resolution(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_comparison_review_resolution(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    transaction_with_dashboard_lock(organization_id, mission_id, dashboard_id, fn row ->
      record_comparison_review_resolution_for_row(
        row,
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts
      )
    end)
  end

  defp record_comparison_review_resolution_for_row(
         %OpsDashboardRow{} = row,
         organization_id,
         mission_id,
         dashboard_id,
         payload,
         opts
       ) do
    with :ok <- reject_archived(row),
         {:ok, request_event} <-
           fetch_comparison_review_request_event(
             organization_id,
             mission_id,
             dashboard_id,
             payload
           ),
         :ok <- validate_comparison_review_resolution_context(request_event, payload),
         :ok <-
           reject_existing_comparison_review_resolution(
             organization_id,
             mission_id,
             dashboard_id,
             request_event.dashboard_lifecycle_event_id
           ) do
      insert_lifecycle_event(
        row,
        row,
        :comparison_review_resolved,
        event_time(opts),
        Keyword.merge(opts,
          payload: comparison_review_resolution_payload(row, request_event, payload)
        )
      )
    end
  end

  @spec record_health_snapshot(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_health_snapshot(organization_id, mission_id, dashboard_id, snapshot, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(snapshot) and is_list(opts) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row ->
        with :ok <- reject_archived(row),
             :ok <- validate_health_snapshot(snapshot) do
          insert_lifecycle_event(
            row,
            row,
            :health_snapshot_captured,
            event_time(opts),
            Keyword.merge(opts, payload: health_snapshot_payload(row, snapshot, opts))
          )
        end
    end
  end

  @spec record_publish_readiness_check(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, LifecycleEvent.t()} | {:error, term()}
  def record_publish_readiness_check(
        organization_id,
        mission_id,
        dashboard_id,
        payload,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(payload) and is_list(opts) do
    case get_row(organization_id, mission_id, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      %OpsDashboardRow{} = row ->
        with :ok <- reject_archived(row) do
          insert_lifecycle_event(
            row,
            row,
            :publish_readiness_checked,
            event_time(opts),
            Keyword.merge(opts, payload: publish_readiness_check_payload(row, payload))
          )
        end
    end
  end

  defp publish_row_with_event(
         row,
         %Version{} = snapshot,
         organization_id,
         mission_id,
         dashboard_id,
         opts
       ) do
    published_at =
      opts
      |> Keyword.get(:published_at, DateTime.utc_now())
      |> DateTime.truncate(:microsecond)

    published_by = Keyword.get(opts, :published_by)

    Repo.transaction(fn ->
      with {:ok, %OpsDashboardRow{} = updated_row} <-
             publish_row(
               row,
               snapshot.version,
               organization_id,
               mission_id,
               dashboard_id,
               published_at,
               published_by
             ),
           {:ok, %Version{} = published_snapshot} <-
             mark_version_published(snapshot),
           {:ok, %LifecycleEvent{}} <-
             insert_lifecycle_event(
               row,
               updated_row,
               :published,
               published_at,
               Keyword.put(opts, :actor_id, published_by)
             ) do
        published_snapshot
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp mark_version_published(%Version{} = snapshot) do
    case Repo.get_by(DashboardVersionRow,
           organization_id: snapshot.organization_id,
           mission_id: snapshot.mission_id,
           dashboard_id: snapshot.dashboard_id,
           version: snapshot.version
         ) do
      nil ->
        {:error, :dashboard_version_not_found}

      %DashboardVersionRow{} = row ->
        row
        |> DashboardVersionRow.publication_changeset()
        |> Repo.update()
        |> case do
          {:ok, %DashboardVersionRow{} = updated_row} ->
            {:ok, DashboardVersionRow.to_domain(updated_row)}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  defp publish_row(
         row,
         version,
         organization_id,
         mission_id,
         dashboard_id,
         published_at,
         published_by
       ) do
    row
    |> OpsDashboardRow.publish_changeset(version, published_at, published_by)
    |> Changeset.optimistic_lock(:lock_version)
    |> Repo.update(stale_error_field: :lock_version)
    |> case do
      {:ok, %OpsDashboardRow{} = updated_row} ->
        {:ok, updated_row}

      {:error, %Changeset{} = changeset} ->
        if stale_lock_error?(changeset) do
          {:error,
           {:dashboard_version_conflict,
            current_document_version(organization_id, mission_id, dashboard_id)}}
        else
          {:error, changeset}
        end
    end
  end

  defp update_lifecycle_row(%OpsDashboardRow{} = row, lifecycle_state) do
    row
    |> OpsDashboardRow.lifecycle_changeset(lifecycle_state)
    |> Changeset.optimistic_lock(:lock_version)
    |> Repo.update(stale_error_field: :lock_version)
    |> case do
      {:ok, %OpsDashboardRow{} = updated_row} ->
        {:ok, updated_row}

      {:error, %Changeset{} = changeset} ->
        if stale_lock_error?(changeset) do
          {:error,
           {:dashboard_version_conflict,
            current_document_version(row.organization_id, row.mission_id, row.dashboard_id)}}
        else
          {:error, changeset}
        end
    end
  end

  defp delete_row(%OpsDashboardRow{} = row, organization_id, mission_id, dashboard_id) do
    row
    |> Changeset.change()
    |> Changeset.optimistic_lock(:lock_version)
    |> Repo.delete(stale_error_field: :lock_version)
    |> case do
      {:ok, %OpsDashboardRow{}} ->
        :ok

      {:error, %Changeset{} = changeset} ->
        if stale_lock_error?(changeset) do
          {:error,
           {:dashboard_version_conflict,
            current_document_version(organization_id, mission_id, dashboard_id)}}
        else
          {:error, changeset}
        end
    end
  end

  defp insert_lifecycle_event(
         %OpsDashboardRow{} = previous_row,
         %OpsDashboardRow{} = current_row,
         event_type,
         %DateTime{} = occurred_at,
         opts
       ) do
    event =
      LifecycleEvent.new(%{
        organization_id: current_row.organization_id,
        mission_id: current_row.mission_id,
        dashboard_id: current_row.dashboard_id,
        event_type: event_type,
        dashboard_version: event_dashboard_version(event_type, current_row),
        previous_lifecycle_state: previous_row.lifecycle_state,
        current_lifecycle_state: current_row.lifecycle_state,
        previous_published_version: OpsDashboardRow.published_version(previous_row),
        current_published_version: OpsDashboardRow.published_version(current_row),
        actor_id: Keyword.get(opts, :actor_id),
        occurred_at: occurred_at,
        payload: lifecycle_event_payload(previous_row, current_row, event_type, opts)
      })

    case Repo.insert(DashboardLifecycleEventRow.changeset(event)) do
      {:ok, %DashboardLifecycleEventRow{} = row} ->
        lifecycle_event = DashboardLifecycleEventRow.to_domain(row)

        with {:ok, %OperationalEvent{}} <- persist_lifecycle_operational_event(lifecycle_event) do
          {:ok, lifecycle_event}
        end

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp persist_lifecycle_operational_event(%LifecycleEvent{} = lifecycle_event) do
    lifecycle_event
    |> OperationalEvent.from_dashboard_lifecycle_event()
    |> then(&OperationalEvents.persist_event(Repo, &1))
  end

  defp lifecycle_event_type("archived"), do: :archived
  defp lifecycle_event_type("active"), do: :restored

  defp event_time(opts) do
    opts
    |> Keyword.get(:occurred_at, DateTime.utc_now())
    |> DateTime.truncate(:microsecond)
  end

  defp event_dashboard_version(:published, %OpsDashboardRow{} = row),
    do: OpsDashboardRow.published_version(row)

  defp event_dashboard_version(_event_type, %OpsDashboardRow{} = row),
    do: OpsDashboardRow.latest_version(row)

  defp lifecycle_event_payload(previous_row, current_row, event_type, opts) do
    base_payload = %{
      "event_type" => Atom.to_string(event_type),
      "dashboard_name" => current_row.name,
      "previous" => %{
        "lifecycle_state" => previous_row.lifecycle_state,
        "published_version" => OpsDashboardRow.published_version(previous_row),
        "draft_version" => OpsDashboardRow.draft_version(previous_row),
        "latest_version" => OpsDashboardRow.latest_version(previous_row)
      },
      "current" => %{
        "lifecycle_state" => current_row.lifecycle_state,
        "published_version" => OpsDashboardRow.published_version(current_row),
        "draft_version" => OpsDashboardRow.draft_version(current_row),
        "latest_version" => OpsDashboardRow.latest_version(current_row)
      }
    }

    Map.merge(base_payload, Keyword.get(opts, :payload, %{}))
  end

  defp comparison_review_request_payload(%OpsDashboardRow{} = row, payload) do
    Map.merge(
      %{
        "schema" => "dashboard_comparison_review_request.v1",
        "request_kind" => "comparison_open_findings_review",
        "source" => "dashboard_comparison_rollup",
        "dashboard_name" => row.name
      },
      payload
    )
  end

  defp comparison_review_resolution_payload(
         %OpsDashboardRow{} = row,
         %LifecycleEvent{} = request_event,
         payload
       ) do
    %{
      "schema" => "dashboard_comparison_review_resolution.v1",
      "request_kind" => "comparison_open_findings_review",
      "source" => "dashboard_activity",
      "source_request_event_id" => request_event.dashboard_lifecycle_event_id,
      "dashboard_name" => row.name
    }
    |> Map.merge(payload)
    |> Map.merge(comparison_review_resolution_source_payload(request_event))
  end

  defp comparison_review_resolution_source_payload(%LifecycleEvent{payload: payload})
       when is_map(payload) do
    bulk_decision_summary = comparison_review_bulk_decision_source_summary(payload)

    %{
      "workflow_intent" => payload_value(payload, "workflow_intent"),
      "open_findings" => payload_value(payload, "open_findings"),
      "source_open_count" => payload_value(payload, "open_count"),
      "source_open_placement_ids" =>
        comparison_review_request_placement_ids(%LifecycleEvent{
          payload: payload
        })
    }
    |> Map.merge(bulk_decision_summary)
    |> Enum.reject(fn {_key, value} -> value in [nil, [], ""] end)
    |> Map.new()
  end

  defp comparison_review_resolution_source_payload(%LifecycleEvent{}), do: %{}

  defp comparison_review_bulk_decision_source_summary(payload) when is_map(payload) do
    findings =
      payload
      |> payload_value("open_findings")
      |> payload_value("findings")
      |> case do
        findings when is_list(findings) -> findings
        _findings -> []
      end

    actionable_items =
      findings
      |> Enum.map(&comparison_review_bulk_decision_actionable_item/1)
      |> Enum.reject(&is_nil/1)

    skipped_items =
      findings
      |> Enum.map(&comparison_review_bulk_decision_skipped_item/1)
      |> Enum.reject(&is_nil/1)

    %{
      "source_bulk_decision_actionable_count" => length(actionable_items),
      "source_bulk_decision_actionable_placement_ids" =>
        comparison_review_bulk_decision_placement_ids(actionable_items),
      "source_bulk_decision_skipped_count" => length(skipped_items),
      "source_bulk_decision_skipped_placement_ids" =>
        comparison_review_bulk_decision_placement_ids(skipped_items),
      "source_bulk_decision_skipped_reasons" =>
        skipped_items
        |> Enum.map(&Map.get(&1, "reason"))
        |> Enum.filter(&present_text?/1)
        |> Enum.uniq()
    }
  end

  defp comparison_review_bulk_decision_actionable_item(finding) when is_map(finding) do
    observation_identity_id = comparison_review_observation_identity_id(finding)

    cond do
      not present_text?(observation_identity_id) ->
        nil

      payload_value(finding, "decision_status") == "applied" ->
        nil

      true ->
        %{
          "placement_id" => payload_value(finding, "placement_id"),
          "observation_identity_id" => observation_identity_id
        }
    end
  end

  defp comparison_review_bulk_decision_actionable_item(_finding), do: nil

  defp comparison_review_bulk_decision_skipped_item(finding) when is_map(finding) do
    cond do
      not present_text?(comparison_review_observation_identity_id(finding)) ->
        %{
          "placement_id" => payload_value(finding, "placement_id"),
          "reason" => "missing_observation_identity"
        }

      payload_value(finding, "decision_status") == "applied" ->
        %{
          "placement_id" => payload_value(finding, "placement_id"),
          "reason" => "already_applied"
        }

      true ->
        nil
    end
  end

  defp comparison_review_bulk_decision_skipped_item(_finding), do: nil

  defp comparison_review_observation_identity_id(finding) when is_map(finding) do
    payload_value(finding, "observation_identity_id") ||
      payload_value(finding, "primary_observation_identity_id") ||
      payload_value(finding, "compare_observation_identity_id")
  end

  defp comparison_review_bulk_decision_placement_ids(items) do
    items
    |> Enum.map(&Map.get(&1, "placement_id"))
    |> Enum.filter(&present_text?/1)
    |> Enum.uniq()
  end

  defp health_snapshot_payload(%OpsDashboardRow{} = row, snapshot, opts) do
    %{
      "schema" => "dashboard_health_snapshot_capture.v1",
      "source" => "dashboard_health_rollup",
      "dashboard_name" => row.name,
      "snapshot_id" => Map.get(snapshot, "snapshot_id"),
      "snapshot_schema" => Map.get(snapshot, "schema"),
      "health_state" => Map.get(snapshot, "state"),
      "health_severity" => Map.get(snapshot, "severity"),
      "captured_reason" => Keyword.get(opts, :captured_reason),
      "snapshot" => snapshot
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp publish_readiness_check_payload(%OpsDashboardRow{} = row, payload) do
    Map.merge(
      %{
        "schema" => "dashboard_publish_readiness_check.v1",
        "source" => "dashboard_publish_readiness",
        "dashboard_name" => row.name
      },
      payload
    )
  end

  defp validate_health_snapshot(snapshot) do
    cond do
      payload_value(snapshot, "schema") != "dashboard_health_snapshot.v1" ->
        {:error, :invalid_health_snapshot}

      payload_value(snapshot, "snapshot_id") in [nil, ""] ->
        {:error, :invalid_health_snapshot}

      true ->
        :ok
    end
  end

  defp fetch_comparison_review_request_event(
         organization_id,
         mission_id,
         dashboard_id,
         payload
       ) do
    request_event_id = payload_value(payload, "source_request_event_id")

    if request_event_id in [nil, ""] do
      {:error, :comparison_review_request_not_found}
    else
      DashboardLifecycleEventRow
      |> where(
        [event],
        event.organization_id == ^organization_id and event.mission_id == ^mission_id and
          event.dashboard_id == ^dashboard_id and
          event.dashboard_lifecycle_event_id == ^request_event_id and
          event.event_type == "comparison_review_requested"
      )
      |> Repo.one()
      |> case do
        %DashboardLifecycleEventRow{} = row ->
          {:ok, DashboardLifecycleEventRow.to_domain(row)}

        nil ->
          {:error, :comparison_review_request_not_found}
      end
    end
  end

  defp validate_comparison_review_resolution_context(%LifecycleEvent{} = request_event, payload) do
    request_placement_ids = comparison_review_request_placement_ids(request_event)
    selected_placement_id = payload_value(payload, "selected_placement_id")
    affected_placement_ids = payload |> payload_value("affected_placement_ids") |> placement_ids()

    cond do
      selected_placement_id in [nil, ""] and affected_placement_ids == [] ->
        :ok

      request_placement_ids == [] ->
        {:error, :comparison_review_resolution_context_mismatch}

      is_binary(selected_placement_id) and selected_placement_id not in request_placement_ids ->
        {:error, :comparison_review_resolution_context_mismatch}

      Enum.any?(affected_placement_ids, &(&1 not in request_placement_ids)) ->
        {:error, :comparison_review_resolution_context_mismatch}

      true ->
        :ok
    end
  end

  defp comparison_review_request_placement_ids(%LifecycleEvent{payload: payload})
       when is_map(payload) do
    ComparisonReviewQueue.request_placements(%{payload: payload})
  end

  defp comparison_review_request_placement_ids(%LifecycleEvent{}), do: []

  defp comparison_review_payload_placement_ids(payload) when is_map(payload) do
    ComparisonReviewQueue.request_placements(%{payload: payload})
  end

  defp comparison_review_payload_placement_ids(_payload), do: []

  defp reject_existing_open_comparison_review_request(
         organization_id,
         mission_id,
         dashboard_id,
         payload
       ) do
    incoming_placement_ids = comparison_review_payload_placement_ids(payload)

    if incoming_placement_ids == [] do
      :ok
    else
      organization_id
      |> list_open_comparison_review_requests(mission_id, dashboard_id)
      |> Enum.find(&comparison_review_request_overlaps?(&1, incoming_placement_ids))
      |> case do
        nil -> :ok
        %LifecycleEvent{} = event -> {:error, {:comparison_review_already_requested, event}}
      end
    end
  end

  defp list_comparison_review_events(organization_id, mission_id, dashboard_id) do
    DashboardLifecycleEventRow
    |> where(
      [event],
      event.organization_id == ^organization_id and event.mission_id == ^mission_id and
        event.dashboard_id == ^dashboard_id and
        event.event_type in ["comparison_review_requested", "comparison_review_resolved"]
    )
    |> order_by([event], asc: event.occurred_at, asc: event.dashboard_lifecycle_event_id)
    |> Repo.all()
    |> Enum.map(&DashboardLifecycleEventRow.to_domain/1)
  end

  defp comparison_review_request_overlaps?(%LifecycleEvent{} = event, incoming_placement_ids) do
    event
    |> comparison_review_request_placement_ids()
    |> Enum.any?(&(&1 in incoming_placement_ids))
  end

  defp reject_existing_comparison_review_resolution(
         organization_id,
         mission_id,
         dashboard_id,
         request_event_id
       ) do
    existing_resolution? =
      DashboardLifecycleEventRow
      |> where(
        [event],
        event.organization_id == ^organization_id and event.mission_id == ^mission_id and
          event.dashboard_id == ^dashboard_id and event.event_type == "comparison_review_resolved" and
          fragment(
            "(? ->> 'source_request_event_id' = ? OR ? -> 'value' ->> 'source_request_event_id' = ?)",
            event.payload,
            ^request_event_id,
            event.payload,
            ^request_event_id
          )
      )
      |> Repo.exists?()

    if existing_resolution? do
      {:error, :comparison_review_already_resolved}
    else
      :ok
    end
  end

  defp payload_value(payload, key) when is_map(payload) and is_binary(key) do
    Map.get(payload, key) || Map.get(payload, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(payload, key)
  end

  defp payload_value(_payload, _key), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""

  defp placement_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(_value), do: []

  defp stale_lock_error?(%Changeset{} = changeset) do
    Keyword.has_key?(changeset.errors, :lock_version)
  end

  defp current_document_version(organization_id, mission_id, dashboard_id) do
    case get_row(organization_id, mission_id, dashboard_id) do
      %OpsDashboardRow{} = row -> OpsDashboardRow.latest_version(row)
      nil -> nil
    end
  end

  defp invalidate_dashboard_runtime(%Document{} = document, lifecycle_action, opts \\ []) do
    RuntimeInvalidation.dashboard_version_changed(%{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document_version: Document.version(document),
      lifecycle_action: lifecycle_action,
      source_version: Keyword.get(opts, :source_version)
    })

    :ok
  end
end
