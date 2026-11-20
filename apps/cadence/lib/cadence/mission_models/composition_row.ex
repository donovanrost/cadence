defmodule Cadence.MissionModels.CompositionRow do
  @moduledoc false
  # A mission composition (D1, #541): immutable by trigger; its layers are CompositionLayerRow.
  use Ecto.Schema

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_compositions" do
    field(:organization_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:composition_id, :string, primary_key: true)
    field(:created_by, :map)

    timestamps()
  end
end
