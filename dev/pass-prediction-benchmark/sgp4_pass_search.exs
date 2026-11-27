# Benchmark for #732 (docs/pass-prediction-design.md): pure-Elixir near-earth SGP4
# (Vallado 2006, WGS72) plus pass search over a synthetic LEO fleet and 15 stations.
# A prototype for the design note, not the production package.
#
# Usage: elixir dev/pass-prediction-benchmark/sgp4_pass_search.exs [spacecraft] [days] [step_s] [concurrency]
# Defaults: 500 spacecraft, 7 days, 60 s coarse step, all schedulers.
defmodule SGP4 do
  @re 6378.135
  @mu 398_600.8
  @xke 60.0 / :math.sqrt(@re * @re * @re / @mu)
  @j2 0.001082616
  @j3 -0.00000253881
  @j4 -0.00000165597
  @j3oj2 @j3 / @j2
  @twopi 2.0 * :math.pi()
  @x2o3 2.0 / 3.0

  def re, do: @re

  # elements: %{no_kozai: rad/min, ecco, inclo, nodeo, argpo, mo, bstar, epoch_jd}
  def init(e) do
    %{no_kozai: nk, ecco: ecco, inclo: inclo, nodeo: nodeo, argpo: argpo, mo: mo, bstar: bstar} =
      e

    ss = 78.0 / @re + 1.0
    qzms2t = :math.pow((120.0 - 78.0) / @re, 4)

    eccsq = ecco * ecco
    omeosq = 1.0 - eccsq
    rteosq = :math.sqrt(omeosq)
    cosio = :math.cos(inclo)
    cosio2 = cosio * cosio
    ak = :math.pow(@xke / nk, @x2o3)
    d1 = 0.75 * @j2 * (3.0 * cosio2 - 1.0) / (rteosq * omeosq)
    del = d1 / (ak * ak)
    adel = ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del / 81.0))
    del = d1 / (adel * adel)
    no = nk / (1.0 + del)
    ao = :math.pow(@xke / no, @x2o3)
    sinio = :math.sin(inclo)
    po = ao * omeosq
    con42 = 1.0 - 5.0 * cosio2
    con41 = -con42 - cosio2 - cosio2
    posq = po * po
    rp = ao * (1.0 - ecco)
    if @twopi / no >= 225.0, do: raise("deep space not in this benchmark")

    isimp = rp < 220.0 / @re + 1.0
    perige = (rp - 1.0) * @re

    {sfour, qzms24} =
      if perige < 156.0 do
        s = if perige < 98.0, do: 20.0, else: perige - 78.0
        {s / @re + 1.0, :math.pow((120.0 - s) / @re, 4)}
      else
        {ss, qzms2t}
      end

    pinvsq = 1.0 / posq
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
           0.375 * @j2 * tsi / psisq * con41 * (8.0 + 3.0 * etasq * (8.0 + etasq)))

    cc1 = bstar * cc2
    cc3 = if ecco > 1.0e-4, do: -2.0 * coef * tsi * @j3oj2 * no * sinio / ecco, else: 0.0
    x1mth2 = 1.0 - cosio2

    cc4 =
      2.0 * no * coef1 * ao * omeosq *
        (eta * (2.0 + 0.5 * etasq) + ecco * (0.5 + 2.0 * etasq) -
           @j2 * tsi / (ao * psisq) *
             (-3.0 * con41 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq)) * :math.cos(2.0 * argpo)))

    cc5 = 2.0 * coef1 * ao * omeosq * (1.0 + 2.75 * (etasq + eeta) + eeta * etasq)
    cosio4 = cosio2 * cosio2
    temp1 = 1.5 * @j2 * pinvsq * no
    temp2 = 0.5 * temp1 * @j2 * pinvsq
    temp3 = -0.46875 * @j4 * pinvsq * pinvsq * no

    mdot =
      no + 0.5 * temp1 * rteosq * con41 +
        0.0625 * temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4)

    argpdot =
      -0.5 * temp1 * con42 + 0.0625 * temp2 * (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
        temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4)

    xhdot1 = -temp1 * cosio

    nodedot =
      xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * cosio2) + 2.0 * temp3 * (3.0 - 7.0 * cosio2)) * cosio

    omgcof = bstar * cc3 * :math.cos(argpo)
    xmcof = if ecco > 1.0e-4, do: -@x2o3 * coef * bstar / eeta, else: 0.0
    nodecf = 3.5 * omeosq * xhdot1 * cc1
    t2cof = 1.5 * cc1

    xlcof =
      if abs(cosio + 1.0) > 1.5e-12,
        do: -0.25 * @j3oj2 * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio),
        else: -0.25 * @j3oj2 * sinio * (3.0 + 5.0 * cosio) / 1.5e-12

    aycof = -0.5 * @j3oj2 * sinio
    delmo = :math.pow(1.0 + eta * :math.cos(mo), 3)
    sinmao = :math.sin(mo)
    x7thm1 = 7.0 * cosio2 - 1.0

    {d2, d3, d4, t3cof, t4cof, t5cof} =
      if isimp do
        {0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
      else
        cc1sq = cc1 * cc1
        d2 = 4.0 * ao * tsi * cc1sq
        temp = d2 * tsi * cc1 / 3.0
        d3 = (17.0 * ao + sfour) * temp
        d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) * cc1

        {d2, d3, d4, d2 + 2.0 * cc1sq, 0.25 * (3.0 * d3 + cc1 * (12.0 * d2 + 10.0 * cc1sq)),
         0.2 * (3.0 * d4 + 12.0 * cc1 * d3 + 6.0 * d2 * d2 + 15.0 * cc1sq * (2.0 * d2 + cc1sq))}
      end

    {isimp, no, ecco, inclo, nodeo, argpo, mo, bstar, mdot, argpdot, nodedot, nodecf, cc1, cc4,
     cc5, t2cof, omgcof, xmcof, eta, delmo, sinmao, d2, d3, d4, t3cof, t4cof, t5cof, aycof, xlcof,
     con41, x1mth2, x7thm1, sinio, cosio}
  end

  # Position in TEME, km. t in minutes since epoch.
  def position(
        {isimp, no, ecco, inclo, nodeo, argpo, mo, bstar, mdot, argpdot, nodedot, nodecf, cc1,
         cc4, cc5, t2cof, omgcof, xmcof, eta, delmo, sinmao, d2, d3, d4, t3cof, t4cof, t5cof,
         aycof, xlcof, con41, x1mth2, x7thm1, sinio, cosio},
        t
      ) do
    xmdf = mo + mdot * t
    argpdf = argpo + argpdot * t
    nodedf = nodeo + nodedot * t
    t2 = t * t
    nodem = nodedf + nodecf * t2
    tempa = 1.0 - cc1 * t
    tempe = bstar * cc4 * t
    templ = t2cof * t2

    {mm, argpm, tempa, tempe, templ} =
      if isimp do
        {xmdf, argpdf, tempa, tempe, templ}
      else
        delomg = omgcof * t
        c = 1.0 + eta * :math.cos(xmdf)
        delm = xmcof * (c * c * c - delmo)
        temp = delomg + delm
        mm = xmdf + temp
        t3 = t2 * t
        t4 = t3 * t

        {mm, argpdf - temp, tempa - d2 * t2 - d3 * t3 - d4 * t4,
         tempe + bstar * cc5 * (:math.sin(mm) - sinmao),
         templ + t3cof * t3 + t4 * (t4cof + t * t5cof)}
      end

    am = :math.pow(@xke / no, @x2o3) * tempa * tempa
    nm = @xke / :math.pow(am, 1.5)
    em = max(ecco - tempe, 1.0e-6)
    mm = mm + no * templ
    xlm = mm + argpm + nodem
    nodem = fmod(nodem)
    argpm = fmod(argpm)
    xlm = fmod(xlm)
    _mm = fmod(xlm - argpm - nodem)
    _ = nm

    axnl = em * :math.cos(argpm)
    temp = 1.0 / (am * (1.0 - em * em))
    aynl = em * :math.sin(argpm) + temp * aycof
    xl = xlm + temp * xlcof * axnl
    u = fmod(xl - nodem)
    {sineo1, coseo1} = kepler(u, axnl, aynl, u, 1)

    ecose = axnl * coseo1 + aynl * sineo1
    esine = axnl * sineo1 - aynl * coseo1
    el2 = axnl * axnl + aynl * aynl
    pl = am * (1.0 - el2)
    rl = am * (1.0 - ecose)
    betal = :math.sqrt(1.0 - el2)
    temp = esine / (1.0 + betal)
    sinu = am / rl * (sineo1 - aynl - axnl * temp)
    cosu = am / rl * (coseo1 - axnl + aynl * temp)
    su = :math.atan2(sinu, cosu)
    sin2u = (cosu + cosu) * sinu
    cos2u = 1.0 - 2.0 * sinu * sinu
    temp = 1.0 / pl
    temp1 = 0.5 * @j2 * temp
    temp2 = temp1 * temp
    mrt = rl * (1.0 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
    su = su - 0.25 * temp2 * x7thm1 * sin2u
    xnode = nodem + 1.5 * temp2 * cosio * sin2u
    xinc = inclo + 1.5 * temp2 * cosio * sinio * cos2u
    sinsu = :math.sin(su)
    cossu = :math.cos(su)
    snod = :math.sin(xnode)
    cnod = :math.cos(xnode)
    sini = :math.sin(xinc)
    cosi = :math.cos(xinc)
    xmx = -snod * cosi
    xmy = cnod * cosi
    k = mrt * @re
    {k * (xmx * sinsu + cnod * cossu), k * (xmy * sinsu + snod * cossu), k * (sini * sinsu)}
  end

  defp kepler(u, axnl, aynl, eo1, ktr) do
    sineo1 = :math.sin(eo1)
    coseo1 = :math.cos(eo1)
    tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / (1.0 - coseo1 * axnl - sineo1 * aynl)
    tem5 = if abs(tem5) >= 0.95, do: if(tem5 > 0, do: 0.95, else: -0.95), else: tem5
    eo1 = eo1 + tem5

    if abs(tem5) >= 1.0e-12 and ktr < 10,
      do: kepler(u, axnl, aynl, eo1, ktr + 1),
      else: {:math.sin(eo1), :math.cos(eo1)}
  end

  defp fmod(x), do: x - @twopi * Float.floor(x / @twopi)

  def gstime(jd) do
    tut1 = (jd - 2_451_545.0) / 36_525.0

    temp =
      -6.2e-6 * tut1 * tut1 * tut1 + 0.093104 * tut1 * tut1 +
        (876_600.0 * 3600.0 + 8_640_184.812866) * tut1 + 67_310.54841

    fmod(temp * :math.pi() / 180.0 / 240.0)
  end
end

defmodule PassSearch do
  @omega_earth_rad_min 7.292115146706979e-5 * 60.0
  @re 6378.135

  def station(lat_deg, lon_deg, alt_km, mask_deg) do
    lat = lat_deg * :math.pi() / 180.0
    lon = lon_deg * :math.pi() / 180.0
    # spherical earth for the benchmark (ellipsoid is the same cost)
    r = @re + alt_km
    up = {:math.cos(lat) * :math.cos(lon), :math.cos(lat) * :math.sin(lon), :math.sin(lat)}
    {ux, uy, uz} = up
    {{r * ux, r * uy, r * uz}, up, :math.sin(mask_deg * :math.pi() / 180.0)}
  end

  # sin(elevation) - sin(mask) for one station at time t (min)
  def f(sat, gst0, st, t), do: elevation(ecef(sat, gst0, t), st)

  def ecef(sat, gst0, t) do
    {x, y, z} = SGP4.position(sat, t)
    th = gst0 + @omega_earth_rad_min * t
    c = :math.cos(th)
    s = :math.sin(th)
    {c * x + s * y, -s * x + c * y, z}
  end

  # A pass that overlaps the window is found whole: one above the mask at the start is traced
  # back to its AOS, one still above it at the end is traced on to its LOS. The search is bounded
  # by the spacecraft's synodic period 2π / (n − ω⊕), the time for it to come round again
  # relative to the rotating earth even when it co-rotates (prograde, equatorial). No pass is
  # longer, at any near-earth period (under 225 min, so at most about 267 min) or mask; if no
  # crossing is found within the bound the pass is counted as unbracketed, never given a
  # clipped AOS or LOS. Every SGP4 propagation is counted once; all stations are evaluated from
  # the same position. Returns {passes, calls, unbracketed}.
  def run(sat, gst0, stations, span_min, step_min) do
    n = trunc(span_min / step_min)
    bound = synodic_min(sat)
    pos0 = ecef(sat, gst0, 0.0)

    {init, {calls, open}} =
      Enum.map_reduce(
        stations,
        {1, 0},
        &start_station(&1, &2, {sat, gst0}, pos0, step_min, bound)
      )

    {sts, passes, calls} =
      Enum.reduce(1..n, {init, 0, calls}, fn i, {sts, passes, calls} ->
        t = i * step_min
        pos = ecef(sat, gst0, t)
        step = &step_station(&1, &2, {sat, gst0}, pos, t, step_min)
        {acc, p, c} = Enum.reduce(sts, {[], passes, calls + 1}, step)
        {Enum.reverse(acc), p, c}
      end)

    # A pass still open at the end; one whose start was unbracketed is already counted.
    Enum.reduce(sts, {passes, calls, open}, fn
      {_st, nil, _v}, acc ->
        acc

      {st, aos, _v}, {p, c, u} ->
        case lead_out({sat, gst0, st}, aos, n * step_min, step_min, bound) do
          {:ok, _los, k} when aos == :unbracketed -> {p, c + k, u}
          {:ok, _los, k} -> {p + 1, c + k, u}
          {:unbracketed, k} when aos == :unbracketed -> {p, c + k, u}
          {:unbracketed, k} -> {p, c + k, u + 1}
        end
    end)
  end

  # A station's state at t = 0: below the mask, or in a pass traced back to its AOS.
  defp start_station(st, {c, u}, {sat, gst0}, pos0, step_min, bound) do
    v = elevation(pos0, st)

    if v < 0,
      do: {{st, nil, v}, {c, u}},
      else: traced_start(st, v, {c, u}, {sat, gst0}, step_min, bound)
  end

  defp traced_start(st, v, {c, u}, {sat, gst0}, step_min, bound) do
    case lead_in({sat, gst0, st}, step_min, bound) do
      {:ok, aos, k} -> {{st, aos, v}, {c + k, u}}
      {:unbracketed, k} -> {{st, :unbracketed, v}, {c + k, u + 1}}
    end
  end

  @doc false
  # The whole pass around t = 0 for a spacecraft above the mask then: {:ok, aos, los} or
  # :unbracketed.
  def pass_around_zero(sat, gst0, st, step_min) do
    ctx = {sat, gst0, st}
    bound = synodic_min(sat)

    with {:ok, aos, _} <- lead_in(ctx, step_min, bound),
         {:ok, los, _} <- lead_out(ctx, aos, 0.0, step_min, bound) do
      {:ok, aos, los}
    else
      {:unbracketed, _k} -> :unbracketed
    end
  end

  # Minutes for the spacecraft to come round again relative to a co-rotating station.
  defp synodic_min(sat), do: 2 * :math.pi() / (elem(sat, 1) - @omega_earth_rad_min)

  defp elevation({x, y, z}, {{sx, sy, sz}, {ux, uy, uz}, smask}) do
    dx = x - sx
    dy = y - sy
    dz = z - sz
    (dx * ux + dy * uy + dz * uz) / :math.sqrt(dx * dx + dy * dy + dz * dz) - smask
  end

  # Above the mask at t = 0: step back until below it, then bisect to the AOS.
  defp lead_in(ctx, step_min, bound), do: lead_in(ctx, -step_min, step_min, bound, 0)

  defp lead_in(ctx, t, step_min, bound, k) do
    cond do
      g(ctx, t) < 0 ->
        {aos, k2} = bisect(ctx, t, t + step_min)
        {:ok, aos, k + 1 + k2}

      t <= -bound ->
        {:unbracketed, k + 1}

      true ->
        lead_in(ctx, t - step_min, step_min, bound, k + 1)
    end
  end

  # Still above the mask at t_end: step on until below it, bisect to the LOS, then find the TCA.
  defp lead_out(ctx, aos, t_end, step_min, bound),
    do: lead_out(ctx, aos, t_end, t_end + step_min, step_min, bound, 0)

  defp lead_out(ctx, aos, t_end, t, step_min, bound, k) do
    cond do
      g(ctx, t) < 0 ->
        {los, k2} = bisect(ctx, t - step_min, t)
        k3 = if aos == :unbracketed, do: 0, else: elem(golden(ctx, aos, los), 1)
        {:ok, los, k + 1 + k2 + k3}

      t >= t_end + bound ->
        {:unbracketed, k + 1}

      true ->
        lead_out(ctx, aos, t_end, t + step_min, step_min, bound, k + 1)
    end
  end

  defp step_station({st, aos, prev}, {acc, p, c}, {sat, gst0}, pos, t, step_min) do
    v = elevation(pos, st)
    ctx = {sat, gst0, st}

    cond do
      prev < 0 and v >= 0 ->
        {a, k} = bisect(ctx, t - step_min, t)
        {[{st, a, v} | acc], p, c + k}

      prev >= 0 and v < 0 and aos == :unbracketed ->
        {_los, k} = bisect(ctx, t - step_min, t)
        {[{st, nil, v} | acc], p, c + k}

      prev >= 0 and v < 0 ->
        {los, k} = bisect(ctx, t - step_min, t)
        {_tca, k2} = golden(ctx, aos, los)
        {[{st, nil, v} | acc], p + 1, c + k + k2}

      true ->
        {[{st, aos, v} | acc], p, c}
    end
  end

  defp g({sat, gst0, st}, t), do: f(sat, gst0, st, t)

  # to 1 s; fa carried so each step costs one evaluation
  defp bisect(ctx, a, b), do: bisect(ctx, a, b, g(ctx, a), 1)

  defp bisect(ctx, a, b, fa, k) do
    if b - a <= 1.0 / 60.0 do
      {b, k}
    else
      m = 0.5 * (a + b)
      fm = g(ctx, m)
      if fa * fm <= 0, do: bisect(ctx, a, m, fa, k + 1), else: bisect(ctx, m, b, fm, k + 1)
    end
  end

  @gr 0.6180339887498949
  # golden section reusing one interior point per step
  defp golden(ctx, a, b) do
    c = b - @gr * (b - a)
    d = a + @gr * (b - a)
    golden(ctx, a, b, {c, g(ctx, c)}, {d, g(ctx, d)}, 2)
  end

  defp golden(ctx, a, b, {c, fc}, {d, fd}, k) do
    cond do
      b - a <= 1.0 / 60.0 ->
        {0.5 * (a + b), k}

      fc > fd ->
        c2 = d - @gr * (d - a)
        golden(ctx, a, d, {c2, g(ctx, c2)}, {c, fc}, k + 1)

      true ->
        d2 = c + @gr * (b - c)
        golden(ctx, c, b, {d, fd}, {d2, g(ctx, d2)}, k + 1)
    end
  end
end

# Missing trailing arguments take their defaults.
[n, days, step_s, conc] =
  System.argv()
  |> Enum.map(&String.to_integer/1)
  |> Enum.concat([500, 7, 60, System.schedulers_online()] |> Enum.drop(length(System.argv())))

deg = :math.pi() / 180.0
epoch_jd = 2_461_370.5
gst0 = SGP4.gstime(epoch_jd)

fleet =
  for i <- 0..(n - 1) do
    alt = 500.0 + rem(i * 37, 100)
    a = (SGP4.re() + alt) / SGP4.re()
    # kozai mean motion in rad/min from semi-major axis (earth radii); xke units
    xke = 60.0 / :math.sqrt(SGP4.re() ** 3 / 398_600.8)
    nk = xke / :math.pow(a, 1.5)

    %{
      no_kozai: nk,
      ecco: 0.0005 + rem(i, 10) * 0.0001,
      inclo: if(rem(i, 2) == 0, do: 53.0, else: 97.6) * deg,
      nodeo: rem(i * 13, 360) * deg,
      argpo: rem(i * 7, 360) * deg,
      mo: rem(i * 29, 360) * deg,
      bstar: 2.0e-5
    }
  end

stations =
  [
    {64.8, -147.7},
    {78.2, 15.4},
    {-72.0, 2.5},
    {35.4, -116.9},
    {40.4, -4.2},
    {-35.4, 149.0},
    {13.6, 144.9},
    {-25.9, 27.7},
    {19.0, -155.7},
    {67.9, 21.1},
    {-53.0, -70.9},
    {1.4, 103.8},
    {51.1, -114.0},
    {-33.1, -70.7},
    {33.0, 131.0}
  ]
  |> Enum.map(fn {lat, lon} -> PassSearch.station(lat, lon, 0.1, 5.0) end)

# Accuracy gate: Vallado's verification case 00005 (tcppver.out), positions in km.
vallado =
  SGP4.init(%{
    no_kozai: 10.82419157 * 2 * :math.pi() / 1440.0,
    ecco: 0.1859667,
    inclo: 34.2682 * deg,
    nodeo: 348.7242 * deg,
    argpo: 331.7664 * deg,
    mo: 19.3264 * deg,
    bstar: 0.28098e-4
  })

for {t, {ex, ey, ez}} <- [
      {0.0, {7022.46529266, -1400.08296755, 0.03995155}},
      {360.0, {-7154.03120202, -3783.17682504, -3536.19412294}},
      {720.0, {-7134.59340119, 6531.68641334, 3260.27186483}},
      {1080.0, {5568.53901181, 4492.06992591, 3863.87641983}}
    ] do
  {x, y, z} = SGP4.position(vallado, t)
  err_m = :math.sqrt((x - ex) ** 2 + (y - ey) ** 2 + (z - ez) ** 2) * 1000
  if err_m > 1.0, do: raise("SGP4 verification failed at t=#{t} min: #{err_m} m")
end

IO.puts("Vallado 00005 verification: within 1 m at 0, 360, 720 and 1080 min")

# Edge gate: a 220-minute, nearly circular equatorial orbit (near-earth, but its passes outlast
# an hour) straight above an equatorial station at t = 0. The whole pass must be found, with
# AOS and LOS at real crossings of the mask, not at a search bound.
long_pass =
  SGP4.init(%{
    no_kozai: 2 * :math.pi() / 220.0,
    ecco: 0.0001,
    inclo: 0.0,
    nodeo: 0.0,
    argpo: 0.0,
    mo: 0.0,
    bstar: 0.0
  })

below = PassSearch.station(0.0, -gst0 / deg, 0.1, 5.0)
{:ok, aos, los} = PassSearch.pass_around_zero(long_pass, gst0, below, 1.0)
one_s = 1.0 / 60.0

crossing? =
  PassSearch.f(long_pass, gst0, below, aos - one_s) < 0 and
    PassSearch.f(long_pass, gst0, below, aos) >= 0 and
    PassSearch.f(long_pass, gst0, below, los - one_s) >= 0 and
    PassSearch.f(long_pass, gst0, below, los) < 0

if not crossing? or aos > -30.0 or los < 30.0,
  do: raise("long-pass edge gate failed: aos=#{aos} los=#{los}")

{1, _calls, 0} = PassSearch.run(long_pass, gst0, [below], 1.0, 1.0)

IO.puts(
  "Long-pass edge gate: 220 min orbit, AOS #{Float.round(aos, 2)} min, LOS #{Float.round(los, 2)} min"
)

span = days * 1440.0
step = step_s / 60.0

{us, results} =
  :timer.tc(fn ->
    fleet
    |> Task.async_stream(
      fn e -> PassSearch.run(SGP4.init(e), gst0, stations, span, step) end,
      max_concurrency: conc,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end)

passes = results |> Enum.map(&elem(&1, 0)) |> Enum.sum()
calls = results |> Enum.map(&elem(&1, 1)) |> Enum.sum()
unbracketed = results |> Enum.map(&elem(&1, 2)) |> Enum.sum()
if unbracketed > 0, do: raise("#{unbracketed} passes found no horizon crossing within the bound")
coarse = n * (trunc(span / step) + 1)

IO.puts(
  "elixir n=#{n} days=#{days} step=#{step_s}s conc=#{conc} stations=15: #{Float.round(us / 1.0e6, 2)} s, passes=#{passes}, sgp4 calls=#{calls} (coarse #{coarse}, refine #{calls - coarse}), otp=#{System.otp_release()}"
)
