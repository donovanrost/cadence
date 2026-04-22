defmodule Cadence.Persistence.Schemas.CatalogArtifactRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.Artifact
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:artifact_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "catalog_artifacts" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:catalog_database_id, :string)
    field(:catalog_family, :string)
    field(:artifact_name, :string)
    field(:format_key, :string)
    field(:format_version, :string)
    field(:media_type, :string)
    field(:source_artifact, :map)
    field(:content_sha256, :string)
    field(:uploaded_by, :map, default: %{})
    field(:uploaded_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :artifact_id,
    :mission_id,
    :catalog_family,
    :artifact_name,
    :format_key,
    :source_artifact,
    :content_sha256,
    :uploaded_at
  ]

  @spec changeset(Artifact.t()) :: Ecto.Changeset.t()
  def changeset(%Artifact{} = artifact) do
    changeset(%__MODULE__{}, artifact)
  end

  @spec changeset(struct(), Artifact.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %Artifact{} = artifact) do
    row
    |> cast(domain_attrs(artifact), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Artifact.t()
  def to_domain(%__MODULE__{} = row) do
    %Artifact{
      artifact_id: row.artifact_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      catalog_database_id: row.catalog_database_id,
      catalog_family: catalog_family(row.catalog_family),
      artifact_name: row.artifact_name,
      format_key: row.format_key,
      format_version: row.format_version,
      media_type: row.media_type,
      source_artifact: JsonDocument.unwrap_value(row.source_artifact),
      content_sha256: row.content_sha256,
      uploaded_by: JsonDocument.unwrap_value(row.uploaded_by),
      uploaded_at: row.uploaded_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%Artifact{} = artifact) do
    %{
      artifact_id: artifact.artifact_id,
      organization_id: artifact.organization_id,
      mission_id: artifact.mission_id,
      catalog_database_id: artifact.catalog_database_id,
      catalog_family: Atom.to_string(artifact.catalog_family),
      artifact_name: artifact.artifact_name,
      format_key: artifact.format_key,
      format_version: artifact.format_version,
      media_type: artifact.media_type,
      source_artifact: JsonDocument.wrap_value(artifact.source_artifact),
      content_sha256: artifact.content_sha256,
      uploaded_by: JsonDocument.wrap_value(artifact.uploaded_by),
      uploaded_at: artifact.uploaded_at,
      metadata: JsonDocument.wrap_value(artifact.metadata)
    }
  end

  defp all_fields do
    [
      :artifact_id,
      :organization_id,
      :mission_id,
      :catalog_database_id,
      :catalog_family,
      :artifact_name,
      :format_key,
      :format_version,
      :media_type,
      :source_artifact,
      :content_sha256,
      :uploaded_by,
      :uploaded_at,
      :metadata
    ]
  end

  defp catalog_family("telemetry"), do: :telemetry
  defp catalog_family("command"), do: :command
  defp catalog_family("combined"), do: :combined
end
