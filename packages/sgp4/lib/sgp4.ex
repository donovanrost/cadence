defmodule Sgp4 do
  @moduledoc """
  Near-earth SGP4 in pure Elixir: a port of Vallado's 2006 reference implementation (WGS72,
  improved mode), checked against Vallado's verification set. Deep-space element sets (a period
  of 225 minutes or more) are refused with `:deep_space_not_supported` until SDP4 lands.

      {:ok, sat} = Sgp4.init(elements)
      {:ok, position_km, velocity_km_s} = Sgp4.propagate(sat, minutes_since_epoch)

  Positions and velocities are in TEME. `Sgp4.Station` and `Sgp4.Passes` turn them into station
  visibility.
  """

  alias Sgp4.{Init, Propagator, Satellite}

  @doc """
  Initializes an element set: a map with `epoch` (`DateTime`, UTC), `mean_motion` (rev/day,
  Kozai, as TLEs and OMMs give it), `eccentricity`, `inclination_deg`, `raan_deg`,
  `arg_perigee_deg`, `mean_anomaly_deg` and `bstar` (1/earth radii). Extra keys are ignored.
  """
  @spec init(Init.elements()) :: {:ok, Satellite.t()} | {:error, atom()}
  defdelegate init(elements), to: Init

  @doc "Position (km) and velocity (km/s) in TEME, `t` minutes from the element-set epoch."
  @spec propagate(Satellite.t(), number()) ::
          {:ok, Propagator.vector(), Propagator.vector()} | {:error, atom()}
  defdelegate propagate(satellite, t), to: Propagator
end
