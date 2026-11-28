defmodule Sgp4.Init do
  @moduledoc """
  SGP4 initialization (Vallado 2006 `sgp4init` and `initl`, near-earth branch, WGS72, improved
  mode). It un-Kozais the mean motion and derives the drag and secular coefficients once per
  element set. An element set with a period of 225 minutes or more is deep space and is refused
  with `:deep_space_not_supported` until SDP4 lands (DECISIONS #114).
  """

  import Sgp4.Constants

  alias Sgp4.{Frames, Propagator, Satellite}

  @deep_space_period_min 225.0
  @deg :math.pi() / 180.0

  @type elements :: %{
          required(:epoch) => DateTime.t(),
          required(:mean_motion) => number(),
          required(:eccentricity) => number(),
          required(:inclination_deg) => number(),
          required(:raan_deg) => number(),
          required(:arg_perigee_deg) => number(),
          required(:mean_anomaly_deg) => number(),
          required(:bstar) => number(),
          optional(atom()) => term()
        }

  @doc """
  Initializes `elements`: the mean motion in rev/day (Kozai, as a TLE or OMM gives it), angles in
  degrees, B* in 1/earth radii. As Vallado's `sgp4init` does, it propagates to the epoch once and
  answers that propagation's error, if any.
  """
  @spec init(elements()) :: {:ok, Satellite.t()} | {:error, atom()}
  def init(%{epoch: %DateTime{} = epoch, mean_motion: mean_motion, eccentricity: ecco} = e)
      when is_number(mean_motion) and is_number(ecco) do
    cond do
      mean_motion <= 0 -> {:error, :mean_motion_not_positive}
      ecco < 0 or ecco >= 1 -> {:error, :mean_elements_out_of_range}
      true -> build(e, epoch, mean_motion * twopi() / 1440.0, ecco * 1.0)
    end
  end

  def init(_elements), do: {:error, :invalid_elements}

  defp build(e, epoch, no_kozai, ecco) do
    inclo = e.inclination_deg * @deg
    l = initl(no_kozai, ecco, inclo)

    if twopi() / l.no >= @deep_space_period_min do
      {:error, :deep_space_not_supported}
    else
      jd = Frames.julian_date(epoch)

      sat =
        coefficients(l, %{
          epoch: epoch,
          jd_epoch: jd,
          gmst_epoch: Frames.gmst(jd),
          ecco: ecco,
          inclo: inclo,
          nodeo: e.raan_deg * @deg,
          argpo: e.arg_perigee_deg * @deg,
          mo: e.mean_anomaly_deg * @deg,
          bstar: e.bstar * 1.0
        })

      case Propagator.propagate(sat, 0.0) do
        {:ok, _position, _velocity} -> {:ok, sat}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Vallado's initl: the un-Kozai'd mean motion and the quantities derived from it.
  defp initl(no_kozai, ecco, inclo) do
    eccsq = ecco * ecco
    omeosq = 1.0 - eccsq
    rteosq = :math.sqrt(omeosq)
    cosio = :math.cos(inclo)
    cosio2 = cosio * cosio
    ak = :math.pow(xke() / no_kozai, x2o3())
    d1 = 0.75 * j2() * (3.0 * cosio2 - 1.0) / (rteosq * omeosq)
    del = d1 / (ak * ak)
    adel = ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del / 81.0))
    del = d1 / (adel * adel)
    no = no_kozai / (1.0 + del)
    ao = :math.pow(xke() / no, x2o3())
    po = ao * omeosq
    con42 = 1.0 - 5.0 * cosio2

    %{
      no: no,
      ao: ao,
      omeosq: omeosq,
      rteosq: rteosq,
      cosio: cosio,
      cosio2: cosio2,
      sinio: :math.sin(inclo),
      con42: con42,
      con41: -con42 - cosio2 - cosio2,
      posq: po * po,
      rp: ao * (1.0 - ecco)
    }
  end

  defp coefficients(l, base) do
    %{ecco: ecco, argpo: argpo, mo: mo, bstar: bstar} = base
    %{ao: ao, no: no, omeosq: omeosq, cosio: cosio, cosio2: cosio2, sinio: sinio} = l
    {sfour, qzms24} = drag_altitude(l.rp)

    pinvsq = 1.0 / l.posq
    tsi = 1.0 / (ao - sfour)
    eta = ao * ecco * tsi
    etasq = eta * eta
    eeta = ecco * eta
    psisq = abs(1.0 - etasq)
    coef = qzms24 * :math.pow(tsi, 4)
    coef1 = coef / :math.pow(psisq, 3.5)

    cc2 =
      coef1 * no *
        (ao * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
           0.375 * j2() * tsi / psisq * l.con41 * (8.0 + 3.0 * etasq * (8.0 + etasq)))

    cc1 = bstar * cc2
    cc3 = if ecco > 1.0e-4, do: -2.0 * coef * tsi * j3oj2() * no * sinio / ecco, else: 0.0
    x1mth2 = 1.0 - cosio2

    cc4 =
      2.0 * no * coef1 * ao * omeosq *
        (eta * (2.0 + 0.5 * etasq) + ecco * (0.5 + 2.0 * etasq) -
           j2() * tsi / (ao * psisq) *
             (-3.0 * l.con41 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) * :math.cos(2.0 * argpo)))

    cc5 = 2.0 * coef1 * ao * omeosq * (1.0 + 2.75 * (etasq + eeta) + eeta * etasq)
    secular = secular_rates(l, pinvsq)
    isimp = l.rp < 220.0 / re() + 1.0

    values =
      base
      |> Map.merge(secular)
      |> Map.merge(%{
        cc1: cc1,
        cc4: cc4,
        cc5: cc5,
        t2cof: 1.5 * cc1,
        omgcof: bstar * cc3 * :math.cos(argpo),
        xmcof: if(ecco > 1.0e-4, do: -x2o3() * coef * bstar / eeta, else: 0.0),
        nodecf: 3.5 * omeosq * secular.xhdot1 * cc1,
        eta: eta,
        delmo: :math.pow(1.0 + eta * :math.cos(mo), 3),
        sinmao: :math.sin(mo),
        aycof: -0.5 * j3oj2() * sinio,
        xlcof: xlcof(cosio, sinio),
        con41: l.con41,
        x1mth2: x1mth2,
        x7thm1: 7.0 * cosio2 - 1.0,
        sinio: sinio,
        cosio: cosio
      })
      |> Map.merge(higher_drag(isimp, cc1, ao, tsi, sfour))

    %Satellite{
      epoch: base.epoch,
      jd_epoch: base.jd_epoch,
      gmst_epoch: base.gmst_epoch,
      no: no,
      ecco: ecco,
      inclo: base.inclo,
      isimp: isimp,
      coefficients:
        Satellite.coefficient_names() |> Enum.map(&Map.fetch!(values, &1)) |> List.to_tuple()
    }
  end

  # Perigee below 156 km lowers the drag reference altitude (Vallado's sfour and qzms24).
  defp drag_altitude(rp) do
    perige = (rp - 1.0) * re()

    if perige < 156.0 do
      s = if perige < 98.0, do: 20.0, else: perige - 78.0
      {s / re() + 1.0, :math.pow((120.0 - s) / re(), 4)}
    else
      {78.0 / re() + 1.0, :math.pow((120.0 - 78.0) / re(), 4)}
    end
  end

  defp secular_rates(l, pinvsq) do
    %{no: no, cosio: cosio, cosio2: cosio2, rteosq: rteosq, con41: con41, con42: con42} = l
    cosio4 = cosio2 * cosio2
    temp1 = 1.5 * j2() * pinvsq * no
    temp2 = 0.5 * temp1 * j2() * pinvsq
    temp3 = -0.46875 * j4() * pinvsq * pinvsq * no
    xhdot1 = -temp1 * cosio

    %{
      xhdot1: xhdot1,
      mdot:
        no + 0.5 * temp1 * rteosq * con41 +
          0.0625 * temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4),
      argpdot:
        -0.5 * temp1 * con42 + 0.0625 * temp2 * (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
          temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4),
      nodedot:
        xhdot1 +
          (0.5 * temp2 * (4.0 - 19.0 * cosio2) + 2.0 * temp3 * (3.0 - 7.0 * cosio2)) * cosio
    }
  end

  # sgp4fix: avoid a divide by zero for an inclination of 180°.
  defp xlcof(cosio, sinio) do
    divisor = if abs(cosio + 1.0) > 1.5e-12, do: 1.0 + cosio, else: 1.5e-12
    -0.25 * j3oj2() * sinio * (3.0 + 5.0 * cosio) / divisor
  end

  defp higher_drag(true, _cc1, _ao, _tsi, _sfour),
    do: %{d2: 0.0, d3: 0.0, d4: 0.0, t3cof: 0.0, t4cof: 0.0, t5cof: 0.0}

  defp higher_drag(false, cc1, ao, tsi, sfour) do
    cc1sq = cc1 * cc1
    d2 = 4.0 * ao * tsi * cc1sq
    temp = d2 * tsi * cc1 / 3.0
    d3 = (17.0 * ao + sfour) * temp
    d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) * cc1

    %{
      d2: d2,
      d3: d3,
      d4: d4,
      t3cof: d2 + 2.0 * cc1sq,
      t4cof: 0.25 * (3.0 * d3 + cc1 * (12.0 * d2 + 10.0 * cc1sq)),
      t5cof:
        0.2 * (3.0 * d4 + 12.0 * cc1 * d3 + 6.0 * d2 * d2 + 15.0 * cc1sq * (2.0 * d2 + cc1sq))
    }
  end
end
