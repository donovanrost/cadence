defmodule Cadence.Persistence.Schemas.SourceEndpointRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.SourceEndpoints.SourceEndpoint

  @primary_key {:source_endpoint_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_source_endpoints" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:spacecraft_id, :string)
    field(:source_ref, :string)
    field(:scid, :integer)
    field(:display_name, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [:source_endpoint_id, :mission_id, :metadata]

  @spec changeset(SourceEndpoint.t()) :: Ecto.Changeset.t()
  def changeset(%SourceEndpoint{} = source_endpoint) do
    %__MODULE__{}
    |> cast(domain_attrs(source_endpoint), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :source_endpoint_id],
      name: :mission_source_endpoints_scope_idx
    )
  end

  @spec to_domain(struct()) :: SourceEndpoint.t()
  def to_domain(%__MODULE__{} = row) do
    %SourceEndpoint{
      source_endpoint_id: row.source_endpoint_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      spacecraft_id: row.spacecraft_id,
      source_ref: row.source_ref,
      scid: row.scid,
      display_name: row.display_name,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%SourceEndpoint{} = source_endpoint) do
    %{
      source_endpoint_id: source_endpoint.source_endpoint_id,
      organization_id: source_endpoint.organization_id,
      mission_id: source_endpoint.mission_id,
      spacecraft_id: source_endpoint.spacecraft_id,
      source_ref: source_endpoint.source_ref,
      scid: source_endpoint.scid,
      display_name: source_endpoint.display_name,
      metadata: JsonDocument.wrap_value(source_endpoint.metadata)
    }
  end

  defp all_fields do
    [
      :source_endpoint_id,
      :organization_id,
      :mission_id,
      :spacecraft_id,
      :source_ref,
      :scid,
      :display_name,
      :metadata
    ]
  end
end
