defmodule Cadence.MissionModels.CompositionNumberRow do
  @moduledoc false
  # A composition's per-mission short number (D2, #543): insert-only, immutable by trigger.
  use Ecto.Schema

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_composition_numbers" do
    field(:organization_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:composition_id, :string, primary_key: true)
    field(:number, :integer)

    timestamps()
  end
end
