defmodule Cadence.GroundNetworks.ProviderAccounts.AccountRow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Dashboards.SecretMetadata
  alias Cadence.GroundNetworks.ProviderAccount
  alias Cadence.Persistence.JsonDocument

  @primary_key {:provider_account_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "provider_accounts" do
    field(:organization_id, :string)
    field(:display_name, :string)
    field(:lifecycle_state, :string)
    field(:active_version, :integer)
    field(:credential_status, :string)
    field(:event_ingestion_status, :string)
    field(:last_validated_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})
    timestamps()
  end

  @fields [
    :provider_account_id,
    :organization_id,
    :display_name,
    :lifecycle_state,
    :active_version,
    :credential_status,
    :event_ingestion_status,
    :last_validated_at,
    :metadata
  ]

  def changeset(%ProviderAccount{} = account), do: changeset(%__MODULE__{}, account)

  def changeset(%__MODULE__{} = row, %ProviderAccount{} = account) do
    row
    |> cast(domain_attrs(account), @fields)
    |> validate_required(@fields -- [:last_validated_at])
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_inclusion(:lifecycle_state, ["active", "archived"])
    |> validate_inclusion(:credential_status, ["active", "revoked", "unknown"])
    |> validate_inclusion(:event_ingestion_status, ["healthy", "degraded", "disabled", "unknown"])
    |> validate_number(:active_version, greater_than: 0)
    |> validate_secret_free(:metadata)
  end

  def to_domain(%__MODULE__{} = row) do
    ProviderAccount.new(%{
      provider_account_id: row.provider_account_id,
      organization_id: row.organization_id,
      display_name: row.display_name,
      lifecycle_state: row.lifecycle_state,
      active_version: row.active_version,
      credential_status: row.credential_status,
      event_ingestion_status: row.event_ingestion_status,
      last_validated_at: row.last_validated_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(account) do
    account
    |> Map.from_struct()
    |> Map.update!(:lifecycle_state, &Atom.to_string/1)
    |> Map.update!(:credential_status, &Atom.to_string/1)
    |> Map.update!(:event_ingestion_status, &Atom.to_string/1)
    |> Map.update!(:metadata, &JsonDocument.wrap_value/1)
  end

  defp validate_secret_free(changeset, field) do
    document = changeset |> get_field(field) |> JsonDocument.unwrap_value()

    if SecretMetadata.contains_secret?(document),
      do: add_error(changeset, field, "must be secret-free"),
      else: changeset
  end
end
