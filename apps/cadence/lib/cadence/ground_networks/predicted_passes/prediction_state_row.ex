defmodule Cadence.GroundNetworks.PredictedPasses.PredictionStateRow do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:mission_id, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "pass_prediction_states" do
    field(:organization_id, :string)
    field(:horizon_end, :utc_datetime_usec)
    field(:computed_at, :utc_datetime_usec)
    field(:unpropagated, :map, default: %{})
    field(:not_bracketed, :map, default: %{})
    field(:search_basis, :map, default: %{})
  end
end
