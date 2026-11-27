defmodule Sgp4.Constants do
  @moduledoc """
  WGS72 gravity constants, as SGP4 is defined against them (Vallado 2006, `wgs72`). Station
  geometry uses WGS84 instead (`Sgp4.Station`): the two are separate on purpose.
  """

  @doc "Earth's equatorial radius, km (WGS72)."
  defmacro re, do: 6378.135

  @doc "Earth's gravitational parameter, km³/s² (WGS72)."
  defmacro mu, do: 398_600.8

  @doc "sqrt(mu) in Earth radii^1.5 per minute: SGP4's `xke`."
  defmacro xke, do: 60.0 / :math.sqrt(6378.135 * 6378.135 * 6378.135 / 398_600.8)

  defmacro j2, do: 0.001082616
  defmacro j3, do: -0.00000253881
  defmacro j4, do: -0.00000165597
  defmacro j3oj2, do: -0.00000253881 / 0.001082616

  @doc "Earth's rotation rate, rad/min."
  defmacro omega_earth_rad_min, do: 7.292115146706979e-5 * 60.0

  defmacro twopi, do: 2.0 * :math.pi()
  defmacro x2o3, do: 2.0 / 3.0
end
