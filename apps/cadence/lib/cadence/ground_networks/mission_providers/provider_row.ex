defmodule Cadence.GroundNetworks.MissionProviders.ProviderRow do
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
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:provider_account_grant_id, :string)
    field(:provider_account_grant_version, :integer)
    field(:provider_type, :string)
    field(:client_key, :string)
    field(:base_url, :string)
    field(:credential_ref, :string)
    field(:environment_ref, :string)
    field(:capabilities_document, :map, default: %{})
    field(:inventory_sync_document, :map, default: %{})
    field(:last_validated_at, :utc_datetime_usec)
    field(:last_synced_at, :utc_datetime_usec)
    field(:delivery_policy_document, :map, default: %{})
    field(:spacecraft_mappings_document, :map, default: %{})
    field(:enabled_service_profile_refs, :map, default: %{})
    field(:enabled_delivery_profile_refs, :map, default: %{})
    field(:permitted_resource_refs, {:array, :string}, default: [])
    field(:preferred_transport_refs, :map, default: %{})
    field(:scheduling_policy_document, :map, default: %{})
    field(:fallback_policy_document, :map, default: %{})
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
    :delivery_policy_document,
    :spacecraft_mappings_document,
    :enabled_service_profile_refs,
    :enabled_delivery_profile_refs,
    :permitted_resource_refs,
    :preferred_transport_refs,
    :scheduling_policy_document,
    :fallback_policy_document,
    :metadata
  ]

  @spec changeset(MissionProvider.t()) :: Ecto.Changeset.t()
  def changeset(%MissionProvider{} = provider) do
    %__MODULE__{}
    |> cast(domain_attrs(provider), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_optional_positive(:provider_account_version)
    |> validate_optional_positive(:provider_account_grant_version)
    |> validate_binding_shape()
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
      provider_account_id: row.provider_account_id,
      provider_account_version: row.provider_account_version,
      provider_account_grant_id: row.provider_account_grant_id,
      provider_account_grant_version: row.provider_account_grant_version,
      provider_type: row.provider_type,
      client_key: row.client_key,
      base_url: row.base_url,
      credential_ref: row.credential_ref,
      environment_ref: row.environment_ref,
      capabilities_document: JsonDocument.unwrap_value(row.capabilities_document),
      inventory_sync_document: JsonDocument.unwrap_value(row.inventory_sync_document),
      last_validated_at: row.last_validated_at,
      last_synced_at: row.last_synced_at,
      delivery_policy_document: JsonDocument.unwrap_value(row.delivery_policy_document),
      spacecraft_mappings_document: JsonDocument.unwrap_value(row.spacecraft_mappings_document),
      enabled_service_profile_refs: JsonDocument.unwrap_items(row.enabled_service_profile_refs),
      enabled_delivery_profile_refs: JsonDocument.unwrap_items(row.enabled_delivery_profile_refs),
      permitted_resource_refs: row.permitted_resource_refs,
      preferred_transport_refs: JsonDocument.unwrap_items(row.preferred_transport_refs),
      scheduling_policy_document: JsonDocument.unwrap_value(row.scheduling_policy_document),
      fallback_policy_document: JsonDocument.unwrap_value(row.fallback_policy_document),
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
      provider_account_id: provider.provider_account_id,
      provider_account_version: provider.provider_account_version,
      provider_account_grant_id: provider.provider_account_grant_id,
      provider_account_grant_version: provider.provider_account_grant_version,
      provider_type: Atom.to_string(provider.provider_type),
      client_key: Atom.to_string(provider.client_key),
      base_url: provider.base_url,
      credential_ref: provider.credential_ref,
      environment_ref: provider.environment_ref,
      capabilities_document: JsonDocument.wrap_value(provider.capabilities_document),
      inventory_sync_document: JsonDocument.wrap_value(provider.inventory_sync_document),
      last_validated_at: provider.last_validated_at,
      last_synced_at: provider.last_synced_at,
      delivery_policy_document: JsonDocument.wrap_value(provider.delivery_policy_document),
      spacecraft_mappings_document:
        JsonDocument.wrap_value(provider.spacecraft_mappings_document),
      enabled_service_profile_refs:
        JsonDocument.wrap_items(provider.enabled_service_profile_refs),
      enabled_delivery_profile_refs:
        JsonDocument.wrap_items(provider.enabled_delivery_profile_refs),
      permitted_resource_refs: provider.permitted_resource_refs,
      preferred_transport_refs: JsonDocument.wrap_items(provider.preferred_transport_refs),
      scheduling_policy_document: JsonDocument.wrap_value(provider.scheduling_policy_document),
      fallback_policy_document: JsonDocument.wrap_value(provider.fallback_policy_document),
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
      :provider_account_id,
      :provider_account_version,
      :provider_account_grant_id,
      :provider_account_grant_version,
      :provider_type,
      :client_key,
      :base_url,
      :credential_ref,
      :environment_ref,
      :capabilities_document,
      :inventory_sync_document,
      :last_validated_at,
      :last_synced_at,
      :delivery_policy_document,
      :spacecraft_mappings_document,
      :enabled_service_profile_refs,
      :enabled_delivery_profile_refs,
      :permitted_resource_refs,
      :preferred_transport_refs,
      :scheduling_policy_document,
      :fallback_policy_document,
      :metadata
    ]
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end

  defp validate_binding_shape(changeset) do
    values =
      Enum.map(
        [
          :provider_account_id,
          :provider_account_version,
          :provider_account_grant_id,
          :provider_account_grant_version
        ],
        &get_field(changeset, &1)
      )

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))) do
      changeset
    else
      add_error(changeset, :provider_account_id, "requires a complete account and grant binding")
    end
  end
end
