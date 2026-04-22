defmodule Cadence.Persistence.Schemas.CatalogRevisionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.Revision
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:catalog_revision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "catalog_revisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:catalog_database_id, :string)
    field(:revision_number, :integer)
    field(:revision_label, :string)
    field(:catalog_family, :string)
    field(:artifact_id, :string)
    field(:import_run_id, :string)
    field(:telemetry_snapshot_id, :string)
    field(:command_snapshot_id, :string)
    field(:content_sha256, :string)
    field(:created_by, :map, default: %{})
    field(:notes, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :catalog_revision_id,
    :mission_id,
    :catalog_database_id,
    :revision_number,
    :revision_label,
    :catalog_family,
    :artifact_id,
    :import_run_id,
    :content_sha256,
    :created_by,
    :metadata
  ]

  @spec changeset(Revision.t()) :: Ecto.Changeset.t()
  def changeset(%Revision{} = revision) do
    changeset(%__MODULE__{}, revision)
  end

  @spec changeset(struct(), Revision.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %Revision{} = revision) do
    row
    |> cast(domain_attrs(revision), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_snapshot_reference()
    |> unique_constraint([:catalog_database_id, :revision_number],
      name: :catalog_revisions_database_number_idx
    )
    |> unique_constraint([:catalog_database_id, :revision_label],
      name: :catalog_revisions_database_label_idx
    )
    |> unique_constraint([:import_run_id], name: :catalog_revisions_import_run_idx)
  end

  @spec to_domain(struct()) :: Revision.t()
  def to_domain(%__MODULE__{} = row) do
    Revision.new(%{
      catalog_revision_id: row.catalog_revision_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      catalog_database_id: row.catalog_database_id,
      revision_number: row.revision_number,
      revision_label: row.revision_label,
      catalog_family: catalog_family(row.catalog_family),
      artifact_id: row.artifact_id,
      import_run_id: row.import_run_id,
      telemetry_snapshot_id: row.telemetry_snapshot_id,
      command_snapshot_id: row.command_snapshot_id,
      content_sha256: row.content_sha256,
      created_by: JsonDocument.unwrap_value(row.created_by),
      notes: row.notes,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Revision{} = revision) do
    %{
      catalog_revision_id: revision.catalog_revision_id,
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      catalog_database_id: revision.catalog_database_id,
      revision_number: revision.revision_number,
      revision_label: revision.revision_label,
      catalog_family: Atom.to_string(revision.catalog_family),
      artifact_id: revision.artifact_id,
      import_run_id: revision.import_run_id,
      telemetry_snapshot_id: revision.telemetry_snapshot_id,
      command_snapshot_id: revision.command_snapshot_id,
      content_sha256: revision.content_sha256,
      created_by: JsonDocument.wrap_value(revision.created_by),
      notes: revision.notes,
      metadata: JsonDocument.wrap_value(revision.metadata)
    }
  end

  defp all_fields do
    [
      :catalog_revision_id,
      :organization_id,
      :mission_id,
      :catalog_database_id,
      :revision_number,
      :revision_label,
      :catalog_family,
      :artifact_id,
      :import_run_id,
      :telemetry_snapshot_id,
      :command_snapshot_id,
      :content_sha256,
      :created_by,
      :notes,
      :metadata
    ]
  end

  defp validate_snapshot_reference(%Ecto.Changeset{} = changeset) do
    telemetry_snapshot_id = get_field(changeset, :telemetry_snapshot_id)
    command_snapshot_id = get_field(changeset, :command_snapshot_id)

    if is_nil(telemetry_snapshot_id) and is_nil(command_snapshot_id) do
      add_error(changeset, :telemetry_snapshot_id, "or command snapshot is required")
    else
      changeset
    end
  end

  defp catalog_family("telemetry"), do: :telemetry
  defp catalog_family("command"), do: :command
  defp catalog_family("combined"), do: :combined
end
