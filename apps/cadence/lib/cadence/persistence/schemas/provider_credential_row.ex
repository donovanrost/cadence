defmodule Cadence.Persistence.Schemas.ProviderCredentialRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.SecretMetadata
  alias Cadence.GroundNetworks.ProviderCredential
  alias Cadence.Persistence.JsonDocument

  @primary_key {:provider_credential_ref, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "provider_credentials" do
    field(:organization_id, :string)
    field(:provider_account_id, :string)
    field(:status, :string)
    field(:registry_version, :integer)
    field(:backend_type, :string)
    field(:backend_key, :string)
    field(:backend_reference, :string)
    field(:registered_at, :utc_datetime_usec)
    field(:last_resolved_at, :utc_datetime_usec)
    field(:last_rotated_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :provider_credential_ref,
    :organization_id,
    :provider_account_id,
    :status,
    :registry_version,
    :backend_type,
    :backend_key,
    :backend_reference,
    :registered_at,
    :last_resolved_at,
    :last_rotated_at,
    :revoked_at,
    :metadata
  ]

  @required_fields @fields --
                     [:backend_reference, :last_resolved_at, :last_rotated_at, :revoked_at]

  @spec changeset(ProviderCredential.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderCredential{} = credential), do: changeset(%__MODULE__{}, credential)

  @spec changeset(struct(), ProviderCredential.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %ProviderCredential{} = credential) do
    row
    |> cast(domain_attrs(credential), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ["active", "revoked"])
    |> validate_inclusion(:backend_type, ["env", "external"])
    |> validate_number(:registry_version, greater_than: 0)
    |> validate_length(:backend_key, min: 1, max: 1_000)
    |> validate_length(:backend_reference, max: 2_000)
    |> validate_metadata()
  end

  @spec to_domain(struct()) :: ProviderCredential.t()
  def to_domain(%__MODULE__{} = row) do
    ProviderCredential.new(%{
      provider_credential_ref: row.provider_credential_ref,
      organization_id: row.organization_id,
      provider_account_id: row.provider_account_id,
      status: row.status,
      registry_version: row.registry_version,
      backend_type: row.backend_type,
      backend_key: row.backend_key,
      backend_reference: row.backend_reference,
      registered_at: row.registered_at,
      last_resolved_at: row.last_resolved_at,
      last_rotated_at: row.last_rotated_at,
      revoked_at: row.revoked_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(credential) do
    credential
    |> Map.from_struct()
    |> Map.update!(:status, &Atom.to_string/1)
    |> Map.update!(:backend_type, &Atom.to_string/1)
    |> Map.update!(:metadata, &JsonDocument.wrap_value/1)
  end

  defp validate_metadata(changeset) do
    changeset
    |> get_field(:metadata)
    |> JsonDocument.unwrap_value()
    |> SecretMetadata.contains_secret?()
    |> case do
      true -> add_error(changeset, :metadata, "must not embed credentials or secrets")
      false -> changeset
    end
  end
end
