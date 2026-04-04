defmodule Cadence.Persistence.Schemas.CatalogImportRunRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.{Diagnostic, ImportRun}
  alias Cadence.Persistence.JsonDocument

  @primary_key {:import_run_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "catalog_import_runs" do
    field(:snapshot_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:artifact_id, :string)
    field(:catalog_family, :string)
    field(:importer_key, :string)
    field(:status, :string)
    field(:imported_definition_count, :integer)
    field(:diagnostics, :map)
    field(:result_document, :map)
    field(:failure_reason, :map)
    field(:requested_by, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :import_run_id,
    :mission_id,
    :artifact_id,
    :catalog_family,
    :importer_key,
    :status,
    :imported_definition_count,
    :started_at
  ]

  @spec changeset(ImportRun.t()) :: Ecto.Changeset.t()
  def changeset(%ImportRun{} = run) do
    changeset(%__MODULE__{}, run)
  end

  @spec changeset(struct(), ImportRun.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %ImportRun{} = run) do
    row
    |> cast(domain_attrs(run), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: ImportRun.t()
  def to_domain(%__MODULE__{} = row) do
    %ImportRun{
      import_run_id: row.import_run_id,
      snapshot_id: row.snapshot_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      artifact_id: row.artifact_id,
      catalog_family: catalog_family(row.catalog_family),
      importer_key: row.importer_key,
      status: status(row.status),
      imported_definition_count: row.imported_definition_count,
      diagnostics:
        row.diagnostics
        |> JsonDocument.unwrap_items()
        |> Enum.map(&Diagnostic.new/1),
      result_document: JsonDocument.unwrap_value(row.result_document),
      failure_reason: JsonDocument.unwrap_value(row.failure_reason),
      requested_by: JsonDocument.unwrap_value(row.requested_by),
      started_at: row.started_at,
      completed_at: row.completed_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%ImportRun{} = run) do
    %{
      import_run_id: run.import_run_id,
      snapshot_id: run.snapshot_id,
      organization_id: run.organization_id,
      mission_id: run.mission_id,
      artifact_id: run.artifact_id,
      catalog_family: Atom.to_string(run.catalog_family),
      importer_key: run.importer_key,
      status: Atom.to_string(run.status),
      imported_definition_count: run.imported_definition_count,
      diagnostics: JsonDocument.wrap_items(run.diagnostics),
      result_document: JsonDocument.wrap_value(run.result_document),
      failure_reason: maybe_wrap_failure_reason(run.failure_reason),
      requested_by: JsonDocument.wrap_value(run.requested_by),
      metadata: JsonDocument.wrap_value(run.metadata),
      started_at: run.started_at,
      completed_at: run.completed_at
    }
  end

  defp all_fields do
    [
      :import_run_id,
      :snapshot_id,
      :organization_id,
      :mission_id,
      :artifact_id,
      :catalog_family,
      :importer_key,
      :status,
      :imported_definition_count,
      :diagnostics,
      :result_document,
      :failure_reason,
      :requested_by,
      :metadata,
      :started_at,
      :completed_at
    ]
  end

  defp catalog_family("telemetry"), do: :telemetry
  defp catalog_family("command"), do: :command
  defp catalog_family("combined"), do: :combined

  defp status("running"), do: :running
  defp status("completed"), do: :completed
  defp status("failed"), do: :failed

  defp maybe_wrap_failure_reason(nil), do: nil
  defp maybe_wrap_failure_reason(reason), do: JsonDocument.wrap_value(reason)
end
