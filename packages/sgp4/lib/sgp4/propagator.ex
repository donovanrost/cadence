defmodule Sgp4.Propagator do
  @moduledoc """
  SGP4 propagation (Vallado 2006 `sgp4`, near-earth branch, WGS72): position (km) and velocity
  (km/s) in TEME at `t` minutes from the element-set epoch.

  Errors follow Vallado's codes: 1 `:mean_elements_out_of_range` (mean eccentricity at or above 1,
  or below −0.001), 2 `:mean_motion_not_positive`, 4 `:semi_latus_rectum_negative` and 6
  `:decayed` (the radius fell below one earth radius). Code 3 is deep space only and code 5 is no
  longer raised by the reference.
  """

  import Sgp4.Constants

  alias Sgp4.Satellite

  @index Satellite.coefficient_names() |> Enum.with_index() |> Map.new()

  # A coefficient by name, compiled to `elem/2` at its index in the satellite's tuple.
  defmacrop k(coefficients, name) do
    quote do: elem(unquote(coefficients), unquote(Map.fetch!(@index, name)))
  end

  @type vector :: {float(), float(), float()}

  @vkmpersec 6378.135 * (60.0 / :math.sqrt(6378.135 * 6378.135 * 6378.135 / 398_600.8)) / 60.0

  @spec propagate(Satellite.t(), number()) :: {:ok, vector(), vector()} | {:error, atom()}
  def propagate(%Satellite{no: no, ecco: ecco} = sat, t) when is_number(t) do
    s = sat.coefficients
    t = t * 1.0
    {mm, argpm, nodem, tempa, tempe, templ} = secular(s, sat.isimp, t)

    am = :math.pow(xke() / no, x2o3()) * tempa * tempa
    nm = xke() / :math.pow(am, 1.5)
    em = ecco - tempe

    cond do
      no <= 0.0 -> {:error, :mean_motion_not_positive}
      em >= 1.0 or em < -0.001 -> {:error, :mean_elements_out_of_range}
      true -> periodics({s, sat.inclo}, am, nm, max(em, 1.0e-6), mm + no * templ, argpm, nodem)
    end
  end

  # Secular gravity and atmospheric drag.
  defp secular(s, isimp, t) do
    xmdf = k(s, :mo) + k(s, :mdot) * t
    argpdf = k(s, :argpo) + k(s, :argpdot) * t
    nodedf = k(s, :nodeo) + k(s, :nodedot) * t
    t2 = t * t
    nodem = nodedf + k(s, :nodecf) * t2
    tempa = 1.0 - k(s, :cc1) * t
    tempe = k(s, :bstar) * k(s, :cc4) * t
    templ = k(s, :t2cof) * t2

    if isimp do
      {xmdf, argpdf, nodem, tempa, tempe, templ}
    else
      delomg = k(s, :omgcof) * t
      c = 1.0 + k(s, :eta) * :math.cos(xmdf)
      delm = k(s, :xmcof) * (c * c * c - k(s, :delmo))
      temp = delomg + delm
      mm = xmdf + temp
      t3 = t2 * t
      t4 = t3 * t

      {mm, argpdf - temp, nodem, tempa - k(s, :d2) * t2 - k(s, :d3) * t3 - k(s, :d4) * t4,
       tempe + k(s, :bstar) * k(s, :cc5) * (:math.sin(mm) - k(s, :sinmao)),
       templ + k(s, :t3cof) * t3 + t4 * (k(s, :t4cof) + t * k(s, :t5cof))}
    end
  end

  # Long-period periodics, Kepler's equation, short-period periodics and the orientation vectors.
  defp periodics({s, _inclo} = sat, am, nm, em, mm, argpm, nodem) do
    xlm = mm + argpm + nodem
    nodem = fmod(nodem)
    argpm = fmod(argpm)
    xlm = fmod(xlm)
    mm = fmod(xlm - argpm - nodem)

    axnl = em * :math.cos(argpm)
    temp = 1.0 / (am * (1.0 - em * em))
    aynl = em * :math.sin(argpm) + temp * k(s, :aycof)
    xl = mm + argpm + nodem + temp * k(s, :xlcof) * axnl
    u = fmod(xl - nodem)
    {sineo1, coseo1} = kepler(u, axnl, aynl, u, 1)

    ecose = axnl * coseo1 + aynl * sineo1
    esine = axnl * sineo1 - aynl * coseo1
    el2 = axnl * axnl + aynl * aynl
    pl = am * (1.0 - el2)

    if pl < 0.0,
      do: {:error, :semi_latus_rectum_negative},
      else: short_period(sat, am, nm, nodem, {sineo1, coseo1, ecose, esine, el2, pl, axnl, aynl})
  end

  defp short_period(
         {s, inclo},
         am,
         nm,
         nodem,
         {sineo1, coseo1, ecose, esine, el2, pl, axnl, aynl}
       ) do
    rl = am * (1.0 - ecose)
    rdotl = :math.sqrt(am) * esine / rl
    rvdotl = :math.sqrt(pl) / rl
    betal = :math.sqrt(1.0 - el2)
    temp = esine / (1.0 + betal)
    sinu = am / rl * (sineo1 - aynl - axnl * temp)
    cosu = am / rl * (coseo1 - axnl + aynl * temp)
    su = :math.atan2(sinu, cosu)
    sin2u = (cosu + cosu) * sinu
    cos2u = 1.0 - 2.0 * sinu * sinu
    temp = 1.0 / pl
    temp1 = 0.5 * j2() * temp
    temp2 = temp1 * temp

    mrt = rl * (1.0 - 1.5 * temp2 * betal * k(s, :con41)) + 0.5 * temp1 * k(s, :x1mth2) * cos2u
    su = su - 0.25 * temp2 * k(s, :x7thm1) * sin2u
    xnode = nodem + 1.5 * temp2 * k(s, :cosio) * sin2u
    xinc = inclo + 1.5 * temp2 * k(s, :cosio) * k(s, :sinio) * cos2u
    mvt = rdotl - nm * temp1 * k(s, :x1mth2) * sin2u / xke()
    rvdot = rvdotl + nm * temp1 * (k(s, :x1mth2) * cos2u + 1.5 * k(s, :con41)) / xke()

    if mrt < 1.0,
      do: {:error, :decayed},
      else: vectors(mrt, mvt, rvdot, su, xnode, xinc)
  end

  defp vectors(mrt, mvt, rvdot, su, xnode, xinc) do
    sinsu = :math.sin(su)
    cossu = :math.cos(su)
    snod = :math.sin(xnode)
    cnod = :math.cos(xnode)
    sini = :math.sin(xinc)
    cosi = :math.cos(xinc)
    xmx = -snod * cosi
    xmy = cnod * cosi
    ux = xmx * sinsu + cnod * cossu
    uy = xmy * sinsu + snod * cossu
    uz = sini * sinsu
    vx = xmx * cossu - cnod * sinsu
    vy = xmy * cossu - snod * sinsu
    vz = sini * cossu
    k = mrt * re()

    {:ok, {k * ux, k * uy, k * uz},
     {(mvt * ux + rvdot * vx) * @vkmpersec, (mvt * uy + rvdot * vy) * @vkmpersec,
      (mvt * uz + rvdot * vz) * @vkmpersec}}
  end

  # Kepler's equation for the eccentric longitude, at most ten Newton steps. As in Vallado's
  # loop, the sine and cosine used afterwards are those taken at the start of the last step.
  defp kepler(u, axnl, aynl, eo1, ktr) do
    sineo1 = :math.sin(eo1)
    coseo1 = :math.cos(eo1)
    tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / (1.0 - coseo1 * axnl - sineo1 * aynl)
    tem5 = if abs(tem5) >= 0.95, do: if(tem5 > 0, do: 0.95, else: -0.95), else: tem5

    if abs(tem5) >= 1.0e-12 and ktr < 10,
      do: kepler(u, axnl, aynl, eo1 + tem5, ktr + 1),
      else: {sineo1, coseo1}
  end

  # C's fmod (the sign of x), as the reference reduces its angles.
  defp fmod(x), do: :math.fmod(x, twopi())
end
