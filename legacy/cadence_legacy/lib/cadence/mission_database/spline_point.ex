defmodule Cadence.MissionDatabase.SplinePoint do
  @moduledoc """
  A point in a spline calibration curve.

  Spline calibrators use a series of points to define a piecewise
  interpolation function for converting raw values to calibrated values.

  ## Example

      # Points for a thermistor calibration
      [
        %SplinePoint{raw: 0.0, calibrated: -40.0},
        %SplinePoint{raw: 1000.0, calibrated: 0.0},
        %SplinePoint{raw: 2000.0, calibrated: 25.0},
        %SplinePoint{raw: 3000.0, calibrated: 50.0},
        %SplinePoint{raw: 4095.0, calibrated: 125.0}
      ]
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :raw, :float
    field :calibrated, :float
  end

  @doc """
  Changeset for creating or updating a spline point.
  """
  def changeset(point, attrs) do
    point
    |> cast(attrs, [:raw, :calibrated])
    |> validate_required([:raw, :calibrated])
  end
end
