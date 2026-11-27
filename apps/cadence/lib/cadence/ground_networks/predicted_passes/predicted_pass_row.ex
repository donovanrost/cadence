defmodule Cadence.GroundNetworks.PredictedPasses.PredictedPassRow do
  @moduledoc false

  use Ecto.Schema

  alias Cadence.GroundNetworks.PredictedPass

  @primary_key {:predicted_pass_id, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "predicted_passes" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:ground_station_id, :string)
    field(:element_set_id, :string)
    field(:aos, :utc_datetime_usec)
    field(:tca, :utc_datetime_usec)
    field(:los, :utc_datetime_usec)
    field(:max_elevation_deg, :float)
    field(:aos_azimuth_deg, :float)
    field(:los_azimuth_deg, :float)
    field(:computed_at, :utc_datetime_usec)
  end

  @spec to_domain(t()) :: PredictedPass.t()
  def to_domain(%__MODULE__{} = row),
    do: struct!(PredictedPass, row |> Map.from_struct() |> Map.delete(:__meta__))
end
