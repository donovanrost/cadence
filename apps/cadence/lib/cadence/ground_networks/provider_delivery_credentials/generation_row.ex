defmodule Cadence.GroundNetworks.ProviderDeliveryCredentials.GenerationRow do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:fingerprint, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_delivery_certificate_generations" do
    field(:credential_ref, :string)
    field(:public_key_fingerprint, :string)
    field(:generation, :integer)
    field(:state, Ecto.Enum, values: [:current, :previous, :revoked])
    field(:expires_at, :utc_datetime)
    field(:overlap_ends_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps()
  end
end
