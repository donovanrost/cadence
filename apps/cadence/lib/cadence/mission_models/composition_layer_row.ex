defmodule Cadence.MissionModels.CompositionLayerRow do
  @moduledoc false
  # One imported layer of a composition, at its mount (D1, #541); FK to the tenant's layer.
  use Ecto.Schema

  @primary_key false

  schema "mission_model_composition_layers" do
    field(:organization_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:composition_id, :string, primary_key: true)
    field(:layer_id, :string, primary_key: true)
    field(:mount, :string)
    field(:position, :integer)
  end
end
