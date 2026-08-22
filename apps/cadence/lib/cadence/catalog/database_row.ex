defmodule Cadence.Catalog.DatabaseRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.Database
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:catalog_database_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "catalog_databases" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:name, :string)
    field(:slug, :string)
    field(:description, :string)
    field(:catalog_family, :string)
    field(:default_importer_key, :string)
    field(:created_by, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :catalog_database_id,
    :mission_id,
    :name,
    :slug,
    :catalog_family,
    :created_by,
    :metadata
  ]

  @spec changeset(Database.t()) :: Ecto.Changeset.t()
  def changeset(%Database{} = database) do
    changeset(%__MODULE__{}, database)
  end

  @spec changeset(struct(), Database.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %Database{} = database) do
    row
    |> cast(domain_attrs(database), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:organization_id, :mission_id, :slug],
      name: :catalog_databases_mission_slug_idx
    )
  end

  @spec to_domain(struct()) :: Database.t()
  def to_domain(%__MODULE__{} = row) do
    Database.new(%{
      catalog_database_id: row.catalog_database_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      name: row.name,
      slug: row.slug,
      description: row.description,
      catalog_family: catalog_family(row.catalog_family),
      default_importer_key: row.default_importer_key,
      created_by: JsonDocument.unwrap_value(row.created_by),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Database{} = database) do
    %{
      catalog_database_id: database.catalog_database_id,
      organization_id: database.organization_id,
      mission_id: database.mission_id,
      name: database.name,
      slug: database.slug,
      description: database.description,
      catalog_family: Atom.to_string(database.catalog_family),
      default_importer_key: database.default_importer_key,
      created_by: JsonDocument.wrap_value(database.created_by),
      metadata: JsonDocument.wrap_value(database.metadata)
    }
  end

  defp all_fields do
    [
      :catalog_database_id,
      :organization_id,
      :mission_id,
      :name,
      :slug,
      :description,
      :catalog_family,
      :default_importer_key,
      :created_by,
      :metadata
    ]
  end

  defp catalog_family("telemetry"), do: :telemetry
  defp catalog_family("command"), do: :command
  defp catalog_family("combined"), do: :combined
end
