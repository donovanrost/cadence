defmodule Cadence.Persistence.Schemas.ContactTransportProfileRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.TransportProfile
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_transport_profiles" do
    field(:transport_profile_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:family_key, :string)
    field(:target_scope, :string)
    field(:configuration, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :transport_profile_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :family_key,
    :target_scope,
    :configuration,
    :metadata
  ]

  @spec changeset(TransportProfile.t()) :: Ecto.Changeset.t()
  def changeset(%TransportProfile{} = transport_profile) do
    %__MODULE__{}
    |> cast(domain_attrs(transport_profile), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :transport_profile_id, :version],
      name: :contact_transport_profiles_scope_idx
    )
  end

  @spec to_domain(struct()) :: TransportProfile.t()
  def to_domain(%__MODULE__{} = row) do
    TransportProfile.new(%{
      transport_profile_id: row.transport_profile_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      family_key: row.family_key,
      target_scope: row.target_scope,
      configuration: JsonDocument.unwrap_value(row.configuration),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%TransportProfile{} = transport_profile) do
    %{
      transport_profile_id: transport_profile.transport_profile_id,
      organization_id: transport_profile.organization_id,
      mission_id: transport_profile.mission_id,
      version: transport_profile.version,
      lifecycle_state: Atom.to_string(transport_profile.lifecycle_state),
      family_key: Atom.to_string(transport_profile.family_key),
      target_scope: Atom.to_string(transport_profile.target_scope),
      configuration: JsonDocument.wrap_value(transport_profile.configuration),
      metadata: JsonDocument.wrap_value(transport_profile.metadata)
    }
  end

  defp all_fields do
    [
      :transport_profile_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :family_key,
      :target_scope,
      :configuration,
      :metadata
    ]
  end
end
