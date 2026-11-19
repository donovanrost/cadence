defmodule Cadence.Catalog.FleetSnapshot.EntryRow do
  @moduledoc "One spacecraft configuration entry, stored once per distinct content."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "activation_fleet_entries" do
    field(:mission_id, :string, primary_key: true)
    field(:entry_sha256, :string, primary_key: true)
    field(:organization_id, :string)
    field(:entry, :map)
    field(:inserted_at, :utc_datetime_usec)
  end
end
