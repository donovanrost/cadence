defmodule Sgp4.Pass do
  @moduledoc """
  One pass of a spacecraft over a station, above the station's elevation mask: AOS, TCA (the
  time of maximum elevation) and LOS to the second, the maximum elevation, and the azimuth at
  AOS and LOS (degrees from north through east).
  """

  @enforce_keys [:station_id, :aos, :tca, :los, :max_elevation_deg]
  defstruct [
    :station_id,
    :aos,
    :tca,
    :los,
    :max_elevation_deg,
    :aos_azimuth_deg,
    :los_azimuth_deg
  ]

  @type t :: %__MODULE__{
          station_id: term(),
          aos: DateTime.t(),
          tca: DateTime.t(),
          los: DateTime.t(),
          max_elevation_deg: float(),
          aos_azimuth_deg: float(),
          los_azimuth_deg: float()
        }
end
