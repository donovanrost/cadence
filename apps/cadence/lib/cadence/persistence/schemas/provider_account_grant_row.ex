defmodule Cadence.Persistence.Schemas.ProviderAccountGrantRow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Dashboards.SecretMetadata
  alias Cadence.GroundNetworks.ProviderAccountGrant
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_account_grants" do
    field(:provider_account_grant_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:restrictions, :map, default: %{})
    field(:granted_by, :string)
    field(:granted_at, :utc_datetime_usec)
    field(:grant_reason, :string)
    field(:revoked_by, :string)
    field(:revoked_at, :utc_datetime_usec)
    field(:revoke_reason, :string)
    field(:metadata, :map, default: %{})
    timestamps()
  end

  @fields [
    :provider_account_grant_id,
    :organization_id,
    :mission_id,
    :provider_account_id,
    :provider_account_version,
    :version,
    :lifecycle_state,
    :restrictions,
    :granted_by,
    :granted_at,
    :grant_reason,
    :revoked_by,
    :revoked_at,
    :revoke_reason,
    :metadata
  ]

  def changeset(%ProviderAccountGrant{} = grant) do
    %__MODULE__{}
    |> cast(domain_attrs(grant), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(
      @fields -- [:granted_by, :grant_reason, :revoked_by, :revoked_at, :revoke_reason]
    )
    |> validate_number(:provider_account_version, greater_than: 0)
    |> validate_number(:version, greater_than: 0)
    |> validate_inclusion(:lifecycle_state, ["active", "revoked"])
    |> validate_secret_free(:restrictions)
    |> validate_secret_free(:metadata)
    |> unique_constraint([:provider_account_grant_id, :version],
      name: :provider_account_grants_scope_idx
    )
  end

  def to_domain(%__MODULE__{} = row) do
    ProviderAccountGrant.new(%{
      provider_account_grant_id: row.provider_account_grant_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      provider_account_id: row.provider_account_id,
      provider_account_version: row.provider_account_version,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      restrictions: unwrap(row.restrictions),
      granted_by: row.granted_by,
      granted_at: row.granted_at,
      grant_reason: row.grant_reason,
      revoked_by: row.revoked_by,
      revoked_at: row.revoked_at,
      revoke_reason: row.revoke_reason,
      metadata: unwrap(row.metadata)
    })
  end

  defp domain_attrs(grant) do
    grant
    |> Map.from_struct()
    |> Map.update!(:lifecycle_state, &Atom.to_string/1)
    |> Map.update!(:restrictions, &JsonDocument.wrap_value/1)
    |> Map.update!(:metadata, &JsonDocument.wrap_value/1)
  end

  defp validate_secret_free(changeset, field) do
    document = changeset |> get_field(field) |> unwrap()

    if SecretMetadata.contains_secret?(document),
      do: add_error(changeset, field, "must be secret-free"),
      else: changeset
  end

  defp unwrap(document), do: JsonDocument.unwrap_value(document)
end
