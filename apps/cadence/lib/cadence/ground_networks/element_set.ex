defmodule Cadence.GroundNetworks.ElementSet do
  @moduledoc """
  A stored element set (#889): one spacecraft's SGP4 mean elements at an epoch, with the raw text
  they were parsed from. Immutable; see `Cadence.GroundNetworks.ElementSets`.
  """

  @enforce_keys [:element_set_id, :organization_id, :mission_id, :spacecraft_id, :epoch]
  defstruct [
    :element_set_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :format,
    :source,
    :raw,
    :object_name,
    :norad_id,
    :element_set_number,
    :epoch,
    :mean_motion,
    :eccentricity,
    :inclination_deg,
    :raan_deg,
    :arg_perigee_deg,
    :mean_anomaly_deg,
    :bstar,
    :mean_motion_dot,
    :mean_motion_ddot,
    :content_sha256,
    :received_at,
    :created_by
  ]

  @type t :: %__MODULE__{}
end
