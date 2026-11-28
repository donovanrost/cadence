defmodule Sgp4.Frames do
  @moduledoc """
  Time and frames for SGP4 output: the Julian date of a UTC time, Greenwich mean sidereal time
  (IAU-82, Vallado's `gstime`), and TEME → earth-fixed by a rotation about z through GMST.

  UT1 is taken as UTC (the difference is under 0.9 s, about 400 m of earth rotation at the
  equator, well under SGP4's own error) and polar motion is ignored (under 20 m).
  """

  import Sgp4.Constants

  @unix_epoch_jd 2_440_587.5

  @doc "The Julian date of `datetime` (UTC), to the microsecond."
  @spec julian_date(DateTime.t()) :: float()
  def julian_date(%DateTime{} = datetime) do
    @unix_epoch_jd + DateTime.to_unix(datetime, :microsecond) / 86_400_000_000
  end

  @doc "Greenwich mean sidereal time, radians in [0, 2π), at Julian date `jd` (UT1)."
  @spec gmst(float()) :: float()
  def gmst(jd) do
    tut1 = (jd - 2_451_545.0) / 36_525.0

    temp =
      -6.2e-6 * tut1 * tut1 * tut1 + 0.093104 * tut1 * tut1 +
        (876_600.0 * 3600.0 + 8_640_184.812866) * tut1 + 67_310.54841

    angle = :math.fmod(temp * :math.pi() / 180.0 / 240.0, twopi())
    if angle < 0.0, do: angle + twopi(), else: angle
  end

  @doc """
  Earth-fixed position (km) of a TEME position, `t` minutes after an epoch whose GMST is
  `gmst_epoch`. GMST advances at the earth's rotation rate between the two.
  """
  @spec teme_to_ecef({float(), float(), float()}, float(), float()) :: {float(), float(), float()}
  def teme_to_ecef({x, y, z}, gmst_epoch, t) do
    theta = gmst_epoch + omega_earth_rad_min() * t
    c = :math.cos(theta)
    s = :math.sin(theta)
    {c * x + s * y, -s * x + c * y, z}
  end
end
