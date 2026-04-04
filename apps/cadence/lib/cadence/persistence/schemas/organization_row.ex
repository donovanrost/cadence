defmodule Cadence.Persistence.Schemas.OrganizationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.JsonDocument

  @primary_key {:organization_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "organizations" do
    field(:slug, :string)
    field(:display_name, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [:organization_id, :slug, :display_name, :metadata]

  @spec changeset(Organization.t()) :: Ecto.Changeset.t()
  def changeset(%Organization{} = organization) do
    %__MODULE__{}
    |> cast(domain_attrs(organization), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:slug], name: :organizations_slug_idx)
  end

  @spec to_domain(struct()) :: Organization.t()
  def to_domain(%__MODULE__{} = row) do
    Organization.new(%{
      organization_id: row.organization_id,
      slug: row.slug,
      display_name: row.display_name,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Organization{} = organization) do
    %{
      organization_id: organization.organization_id,
      slug: organization.slug,
      display_name: organization.display_name,
      metadata: JsonDocument.wrap_value(organization.metadata)
    }
  end

  defp all_fields do
    [:organization_id, :slug, :display_name, :metadata]
  end
end
