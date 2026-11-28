defmodule Cadence.GroundNetworks.PredictedPass do
  @moduledoc """
  One predicted pass (#891): a spacecraft above a station's elevation mask, computed with SGP4
  from the spacecraft's current element set. AOS, TCA and LOS are to the second; azimuths are
  degrees from north through east. See `Cadence.GroundNetworks.PredictedPasses`.
  """

  @enforce_keys [:predicted_pass_id, :mission_id, :spacecraft_id, :ground_station_id, :aos]
  defstruct [
    :predicted_pass_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :ground_station_id,
    :element_set_id,
    :aos,
    :tca,
    :los,
    :max_elevation_deg,
    :aos_azimuth_deg,
    :los_azimuth_deg,
    :computed_at
  ]

  @type t :: %__MODULE__{
          predicted_pass_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          spacecraft_id: binary(),
          ground_station_id: binary(),
          element_set_id: binary(),
          aos: DateTime.t(),
          tca: DateTime.t(),
          los: DateTime.t(),
          max_elevation_deg: float(),
          aos_azimuth_deg: float() | nil,
          los_azimuth_deg: float() | nil,
          computed_at: DateTime.t()
        }
end
