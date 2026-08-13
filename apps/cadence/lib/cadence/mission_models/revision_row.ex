defmodule Cadence.MissionModels.RevisionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.Revision
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:revision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_revisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:status, :string)
    field(:compiler_version, :string)
    field(:content_sha256, :string)
    field(:declaration_count, :integer)
    field(:diagnostic_count, :integer)
    field(:revision_document, :map)
    field(:approved_by, :map)
    field(:approved_at, :utc_datetime_usec)
    field(:rejected_by, :map)
    field(:rejected_at, :utc_datetime_usec)

    timestamps()
  end

  @spec changeset(Revision.t()) :: Ecto.Changeset.t()
  def changeset(%Revision{} = revision) do
    %__MODULE__{}
    |> cast(attrs(revision), fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required([
      :revision_id,
      :mission_id,
      :status,
      :compiler_version,
      :content_sha256,
      :declaration_count,
      :diagnostic_count,
      :revision_document
    ])
    |> unique_constraint([:mission_id, :content_sha256])
  end

  @spec status_changeset(struct(), atom(), map(), DateTime.t()) :: Ecto.Changeset.t()
  def status_changeset(%__MODULE__{} = row, :approved, actor, at) do
    change(row,
      status: "approved",
      approved_by: JsonDocument.wrap_value(actor),
      approved_at: at,
      rejected_by: nil,
      rejected_at: nil
    )
  end

  def status_changeset(%__MODULE__{} = row, :rejected, actor, at) do
    change(row,
      status: "rejected",
      rejected_by: JsonDocument.wrap_value(actor),
      rejected_at: at
    )
  end

  @spec to_domain(struct()) :: Revision.t()
  def to_domain(%__MODULE__{} = row) do
    row.revision_document
    |> JsonDocument.unwrap_value()
    |> Map.merge(%{
      "revision_id" => row.revision_id,
      "organization_id" => row.organization_id,
      "mission_id" => row.mission_id,
      "status" => row.status,
      "compiler_version" => row.compiler_version,
      "content_sha256" => row.content_sha256
    })
    |> Revision.new()
  end

  defp attrs(revision) do
    %{
      revision_id: revision.revision_id,
      organization_id: revision.organization_id,
      mission_id: revision.mission_id,
      status: Atom.to_string(revision.status),
      compiler_version: revision.compiler_version,
      content_sha256: revision.content_sha256,
      declaration_count: map_size(revision.declarations),
      diagnostic_count: length(revision.diagnostics),
      revision_document: JsonDocument.wrap_value(revision)
    }
  end

  defp fields do
    [
      :revision_id,
      :organization_id,
      :mission_id,
      :status,
      :compiler_version,
      :content_sha256,
      :declaration_count,
      :diagnostic_count,
      :revision_document
    ]
  end
end
