defmodule Cadence.Persistence.Schemas.ServiceIdentityRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Persistence.JsonDocument

  @primary_key {:service_identity_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "service_identities" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:display_name, :string)
    field(:capabilities, {:array, :string}, default: [])
    field(:lifecycle_state, :string)
    field(:token_digest, :string)
    field(:token_hint, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :service_identity_id,
    :organization_id,
    :display_name,
    :capabilities,
    :lifecycle_state,
    :token_digest,
    :token_hint,
    :metadata
  ]

  @spec changeset(ServiceIdentity.t(), binary()) :: Ecto.Changeset.t()
  def changeset(%ServiceIdentity{} = service_identity, api_token) when is_binary(api_token) do
    %__MODULE__{}
    |> cast(domain_attrs(service_identity, api_token), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:token_digest], name: :service_identities_token_digest_idx)
  end

  @spec to_domain(struct()) :: ServiceIdentity.t()
  def to_domain(%__MODULE__{} = row) do
    ServiceIdentity.new(%{
      service_identity_id: row.service_identity_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      display_name: row.display_name,
      capabilities: Enum.map(row.capabilities, &ServiceIdentity.normalize_capability/1),
      lifecycle_state: row.lifecycle_state,
      token_hint: row.token_hint,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%ServiceIdentity{} = service_identity, api_token) do
    %{
      service_identity_id: service_identity.service_identity_id,
      organization_id: service_identity.organization_id,
      mission_id: service_identity.mission_id,
      display_name: service_identity.display_name,
      capabilities: Enum.map(service_identity.capabilities, &Atom.to_string/1),
      lifecycle_state: Atom.to_string(service_identity.lifecycle_state),
      token_digest: digest_api_token(api_token),
      token_hint: token_hint(api_token),
      metadata: JsonDocument.wrap_value(service_identity.metadata)
    }
  end

  defp all_fields do
    [
      :service_identity_id,
      :organization_id,
      :mission_id,
      :display_name,
      :capabilities,
      :lifecycle_state,
      :token_digest,
      :token_hint,
      :metadata
    ]
  end

  defp digest_api_token(api_token) do
    :sha256
    |> :crypto.hash(api_token)
    |> Base.encode16(case: :lower)
  end

  defp token_hint(api_token) do
    api_token
    |> String.slice(-6, 6)
  end
end
