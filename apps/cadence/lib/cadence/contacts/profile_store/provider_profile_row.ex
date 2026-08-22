defmodule Cadence.Contacts.ProfileStore.ProviderProfileRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_provider_profiles" do
    field(:provider_profile_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:adapter_key, :string)
    field(:configuration, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :provider_profile_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :adapter_key,
    :configuration,
    :metadata
  ]

  @spec changeset(ProviderProfile.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderProfile{} = provider_profile) do
    %__MODULE__{}
    |> cast(domain_attrs(provider_profile), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :provider_profile_id, :version],
      name: :contact_provider_profiles_scope_idx
    )
  end

  @spec to_domain(struct()) :: ProviderProfile.t()
  def to_domain(%__MODULE__{} = row) do
    ProviderProfile.new(%{
      provider_profile_id: row.provider_profile_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      adapter_key: row.adapter_key,
      configuration: JsonDocument.unwrap_value(row.configuration),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%ProviderProfile{} = provider_profile) do
    %{
      provider_profile_id: provider_profile.provider_profile_id,
      organization_id: provider_profile.organization_id,
      mission_id: provider_profile.mission_id,
      version: provider_profile.version,
      lifecycle_state: Atom.to_string(provider_profile.lifecycle_state),
      adapter_key: Atom.to_string(provider_profile.adapter_key),
      configuration: JsonDocument.wrap_value(provider_profile.configuration),
      metadata: JsonDocument.wrap_value(provider_profile.metadata)
    }
  end

  defp all_fields do
    [
      :provider_profile_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :adapter_key,
      :configuration,
      :metadata
    ]
  end
end
