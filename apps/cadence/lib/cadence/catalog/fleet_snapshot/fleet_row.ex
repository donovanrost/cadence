defmodule Cadence.Catalog.FleetSnapshot.FleetRow do
  @moduledoc "A content-addressed activation fleet (metadata v2 points at it by hash)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "activation_fleets" do
    field(:mission_id, :string, primary_key: true)
    field(:fleet_sha256, :string, primary_key: true)
    field(:organization_id, :string)
    field(:spacecraft_count, :integer)
    field(:inserted_at, :utc_datetime_usec)
  end
end
