defmodule Cadence.GroundNetworks.ElementSets.OmmDocument do
  @moduledoc """
  A stored element set as a CCSDS OMM in JSON form, with the keys CelesTrak publishes (#968):
  what Cadence uploads to a provider that accepts ephemeris uploads. The values are the parsed
  mean elements, so a TLE and an OMM of the same orbit give the same document.
  """

  alias Cadence.GroundNetworks.ElementSet

  @spec from_element_set(ElementSet.t()) :: map()
  def from_element_set(%ElementSet{} = set) do
    %{
      "OBJECT_NAME" => set.object_name,
      "NORAD_CAT_ID" => set.norad_id,
      "ELEMENT_SET_NO" => set.element_set_number,
      "CENTER_NAME" => "EARTH",
      "REF_FRAME" => "TEME",
      "TIME_SYSTEM" => "UTC",
      "MEAN_ELEMENT_THEORY" => "SGP4",
      "EPOCH" => set.epoch |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
      "MEAN_MOTION" => set.mean_motion,
      "ECCENTRICITY" => set.eccentricity,
      "INCLINATION" => set.inclination_deg,
      "RA_OF_ASC_NODE" => set.raan_deg,
      "ARG_OF_PERICENTER" => set.arg_perigee_deg,
      "MEAN_ANOMALY" => set.mean_anomaly_deg,
      "BSTAR" => set.bstar,
      "MEAN_MOTION_DOT" => set.mean_motion_dot,
      "MEAN_MOTION_DDOT" => set.mean_motion_ddot
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
