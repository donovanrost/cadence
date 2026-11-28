defmodule Cadence.GroundNetworks.ProviderDeliveryCredentials.CredentialRow do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:credential_ref, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_delivery_credentials" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_id, :string)
    field(:provider_account_id, :string)
    field(:provider_account_grant_id, :string)
    field(:provider_binding_id, :string)
    field(:retired_at, :utc_datetime_usec)
    timestamps()
  end
end
