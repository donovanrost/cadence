defmodule Cadence.Catalog.FleetSnapshot.MemberRow do
  @moduledoc "A spacecraft's membership in a fleet, with the fields readers filter on."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "activation_fleet_members" do
    field(:mission_id, :string, primary_key: true)
    field(:fleet_sha256, :string, primary_key: true)
    field(:spacecraft_id, :string, primary_key: true)
    field(:organization_id, :string)
    field(:entry_sha256, :string)
    field(:source_endpoint_ids, {:array, :string})
    field(:commanding_enabled, :boolean)
    field(:catalog_revision_id, :string)
    field(:mission_model_sha256, :string)
  end
end
