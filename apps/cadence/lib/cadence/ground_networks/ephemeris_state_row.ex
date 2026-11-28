defmodule Cadence.GroundNetworks.EphemerisStateRow do
  @moduledoc "A `provider_ephemeris_states` row (#968); see `Cadence.GroundNetworks.EphemerisStates`."
  use Ecto.Schema

  @primary_key false
  schema "provider_ephemeris_states" do
    field(:organization_id, :string)
    field(:mission_id, :string, primary_key: true)
    field(:provider_id, :string, primary_key: true)
    field(:spacecraft_id, :string, primary_key: true)
    field(:status, :string)
    field(:element_set_id, :string)
    field(:content_sha256, :string)
    field(:provider_spacecraft_ref, :string)
    field(:provider_version, :integer)
    field(:bound_provider_version, :integer)
    field(:attempts, :integer, default: 0)
    # A closed code only (`EphemerisReasons`), never a provider's own text (#972).
    field(:reason, :string)
    field(:next_retry_at, :utc_datetime_usec)
    # When the pair entered its current outcome (#972).
    field(:outcome_since, :utc_datetime_usec)
    field(:updated_at, :utc_datetime_usec)
  end
end
