defmodule Cadence.Persistence.Schemas.DashboardVersionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.{Document, Version}
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @primary_key {:dashboard_version_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "dashboard_versions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:version, :integer)
    field(:document, :map)
    field(:snapshot_kind, Ecto.Enum, values: [:draft_save, :publish, :revert, :migration])
    field(:parent_version, :integer)
    field(:based_on_version, :integer)
    field(:schema_version, :integer)
    field(:change_summary, :string)
    field(:created_by, :string)

    timestamps()
  end

  @fields [
    :dashboard_version_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :version,
    :document,
    :snapshot_kind,
    :parent_version,
    :based_on_version,
    :schema_version,
    :change_summary,
    :created_by
  ]

  @required_fields [
    :dashboard_version_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :version,
    :document,
    :snapshot_kind,
    :schema_version
  ]

  @spec changeset(Version.t()) :: Ecto.Changeset.t()
  def changeset(%Version{} = version) do
    %__MODULE__{}
    |> cast(attrs(version), @fields)
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_number(:schema_version, greater_than: 0)
    |> validate_length(:change_summary, max: 500)
    |> unique_constraint([:organization_id, :mission_id, :dashboard_id, :version],
      name: :dashboard_versions_scope_version_idx
    )
  end

  @spec publication_changeset(struct()) :: Ecto.Changeset.t()
  def publication_changeset(%__MODULE__{} = row) do
    row
    |> cast(%{snapshot_kind: :publish}, [:snapshot_kind])
    |> validate_required([:snapshot_kind])
  end

  @spec to_domain(struct()) :: Version.t()
  def to_domain(%__MODULE__{} = row) do
    %Version{
      dashboard_version_id: row.dashboard_version_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      dashboard_id: row.dashboard_id,
      version: row.version,
      document: Document.from_map(row.document),
      snapshot_kind: row.snapshot_kind,
      parent_version: row.parent_version,
      based_on_version: row.based_on_version,
      schema_version: row.schema_version,
      change_summary: row.change_summary,
      created_by: row.created_by,
      inserted_at: row.inserted_at
    }
  end

  defp attrs(%Version{} = version) do
    %{
      dashboard_version_id: version.dashboard_version_id || Ids.new("dashboard_version"),
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      dashboard_id: version.dashboard_id,
      version: version.version,
      document: JsonDocument.encode(Document.to_map(version.document)),
      snapshot_kind: version.snapshot_kind,
      parent_version: version.parent_version,
      based_on_version: version.based_on_version,
      schema_version: version.schema_version,
      change_summary: version.change_summary,
      created_by: version.created_by
    }
  end
end
