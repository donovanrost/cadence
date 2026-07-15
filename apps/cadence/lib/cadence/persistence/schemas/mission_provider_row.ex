defmodule Cadence.Persistence.Schemas.MissionProviderRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "mission_providers" do
    field(:provider_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:display_name, :string)
    field(:provider_type, :string)
    field(:client_key, :string)
    field(:base_url, :string)
    field(:credential_ref, :string)
    field(:environment_ref, :string)
    field(:capabilities_document, :map, default: %{})
    field(:inventory_sync_document, :map, default: %{})
    field(:last_validated_at, :utc_datetime_usec)
    field(:last_synced_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :provider_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :display_name,
    :provider_type,
    :client_key,
    :base_url,
    :credential_ref,
    :environment_ref,
    :capabilities_document,
    :inventory_sync_document,
    :metadata
  ]

  @spec changeset(MissionProvider.t()) :: Ecto.Changeset.t()
  def changeset(%MissionProvider{} = provider) do
    %__MODULE__{}
    |> cast(domain_attrs(provider), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_length(:base_url, min: 1, max: 2_000)
    |> validate_length(:credential_ref, min: 1, max: 500)
    |> validate_length(:environment_ref, min: 1, max: 500)
    |> unique_constraint([:mission_id, :provider_id, :version],
      name: :mission_providers_scope_idx
    )
  end

  @spec to_domain(struct()) :: MissionProvider.t()
  def to_domain(%__MODULE__{} = row) do
    MissionProvider.new(%{
      provider_id: row.provider_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      display_name: row.display_name,
      provider_type: row.provider_type,
      client_key: row.client_key,
      base_url: row.base_url,
      credential_ref: row.credential_ref,
      environment_ref: row.environment_ref,
      capabilities_document: JsonDocument.unwrap_value(row.capabilities_document),
      inventory_sync_document: JsonDocument.unwrap_value(row.inventory_sync_document),
      last_validated_at: row.last_validated_at,
      last_synced_at: row.last_synced_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%MissionProvider{} = provider) do
    %{
      provider_id: provider.provider_id,
      organization_id: provider.organization_id,
      mission_id: provider.mission_id,
      version: provider.version,
      lifecycle_state: Atom.to_string(provider.lifecycle_state),
      display_name: provider.display_name,
      provider_type: Atom.to_string(provider.provider_type),
      client_key: Atom.to_string(provider.client_key),
      base_url: provider.base_url,
      credential_ref: provider.credential_ref,
      environment_ref: provider.environment_ref,
      capabilities_document: JsonDocument.wrap_value(provider.capabilities_document),
      inventory_sync_document: JsonDocument.wrap_value(provider.inventory_sync_document),
      last_validated_at: provider.last_validated_at,
      last_synced_at: provider.last_synced_at,
      metadata: JsonDocument.wrap_value(provider.metadata)
    }
  end

  defp all_fields do
    [
      :provider_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :display_name,
      :provider_type,
      :client_key,
      :base_url,
      :credential_ref,
      :environment_ref,
      :capabilities_document,
      :inventory_sync_document,
      :last_validated_at,
      :last_synced_at,
      :metadata
    ]
  end
end
