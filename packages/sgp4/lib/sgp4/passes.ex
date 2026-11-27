defmodule Sgp4.Passes do
  @moduledoc """
  Station visibility for one spacecraft over a window (#732 slice 2, docs/pass-prediction-design.md).

  - **Coarse grid.** The spacecraft is propagated on a grid (60 s by default, `:step_s`) from the
    window start, rotated TEME → earth-fixed by GMST, and every station is evaluated from that
    one position.
  - **Refinement.** A sign change of `sin(el) − sin(mask)` between grid points brackets an AOS or
    LOS, refined by bisection to 1 s; the TCA is found by golden section to 1 s.
  - **Window ends.** A pass that overlaps the window is found whole: one above the mask at the
    window start is traced back to its AOS, one still open at the end is traced on to its LOS.
    Both directions are bounded by the spacecraft's synodic period, 2π / (n − ω⊕), which no pass
    can outlast at any near-earth period or mask. A pass with no crossing inside the bound is
    answered as `{:error, :pass_not_bracketed, ...}`, never with a clipped time.
  - **Short passes.** A pass shorter than the grid step can fall between two grid points and be
    missed; at 60 s that is a grazing pass shorter than any schedulable contact.

  Every propagation is counted in `propagations`.
  """

  alias Sgp4.{Pass, Satellite, Station}
  alias Sgp4.Passes.Refine

  import Sgp4.Constants, only: [omega_earth_rad_min: 0, twopi: 0]

  @default_step_s 60

  @type unbracketed :: {:error, :pass_not_bracketed, %{station_id: term(), near: DateTime.t()}}
  @type result :: %{
          passes: [Pass.t()],
          unbracketed: [unbracketed()],
          propagations: non_neg_integer()
        }

  @doc """
  The passes of `satellite` over `stations` that overlap `[from, to)`, ordered by AOS. A
  propagation error (the spacecraft decays inside the window) answers `{:error, {reason, at}}`.
  """
  @spec search(Satellite.t(), [Station.t()], DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, result()} | {:error, {atom(), DateTime.t()}}
  def search(%Satellite{} = sat, stations, %DateTime{} = from, %DateTime{} = to, opts \\ [])
      when is_list(stations) do
    step = Keyword.get(opts, :step_s, @default_step_s) / 60.0
    t_from = minutes(sat, from)
    t_to = minutes(sat, to)

    if t_to <= t_from or stations == [] do
      {:ok, %{passes: [], unbracketed: [], propagations: 0}}
    else
      run(sat, stations, t_from, t_to, step)
    end
  catch
    {:sgp4_error, reason, t} -> {:error, {reason, at(sat, t)}}
  end

  @doc "Minutes for the spacecraft to come round again relative to a co-rotating station."
  @spec synodic_min(Satellite.t()) :: float()
  def synodic_min(%Satellite{no: no}), do: twopi() / (no - omega_earth_rad_min())

  defp run(sat, stations, t_from, t_to, step) do
    bound = synodic_min(sat)
    n = ceil((t_to - t_from) / step)
    position = Refine.ecef(sat, t_from)

    {states, acc} =
      Enum.map_reduce(
        stations,
        %{found: [], calls: 1},
        &start(&1, &2, sat, position, t_from, step, bound)
      )

    {states, acc} =
      Enum.reduce(1..n//1, {states, acc}, fn i, {states, acc} ->
        t = t_from + i * step
        position = Refine.ecef(sat, t)
        acc = %{acc | calls: acc.calls + 1}
        Enum.map_reduce(states, acc, &step_station(&1, &2, sat, position, t, step))
      end)

    t_end = t_from + n * step
    acc = Enum.reduce(states, acc, &finish(&1, &2, sat, t_end, step, bound))
    {passes, unbracketed} = Enum.split_with(acc.found, &match?(%Pass{}, &1))

    {:ok,
     %{
       passes:
         passes
         |> Enum.filter(&(DateTime.compare(&1.aos, at(sat, t_to)) == :lt))
         |> Enum.sort_by(&DateTime.to_unix(&1.aos)),
       unbracketed: Enum.reverse(unbracketed),
       propagations: acc.calls
     }}
  end

  # A station's state at the window start: below the mask, or inside a pass traced to its AOS.
  defp start(station, acc, sat, position, t_from, step, bound) do
    v = Station.above_mask(station, position)

    if v < 0 do
      {{station, nil, v}, acc}
    else
      case Refine.lead_in({sat, station}, t_from, step, bound) do
        {:ok, aos, k} ->
          {{station, aos, v}, %{acc | calls: acc.calls + k}}

        {:unbracketed, k} ->
          found = [unbracketed(sat, station, t_from) | acc.found]
          {{station, :unbracketed, v}, %{acc | calls: acc.calls + k, found: found}}
      end
    end
  end

  defp step_station({station, open, prev}, acc, sat, position, t, step) do
    v = Station.above_mask(station, position)
    ctx = {sat, station}

    cond do
      prev < 0 and v >= 0 ->
        {aos, k} = Refine.bisect(ctx, t - step, t)
        {{station, aos, v}, %{acc | calls: acc.calls + k}}

      prev >= 0 and v < 0 and open == :unbracketed ->
        {{station, nil, v}, acc}

      prev >= 0 and v < 0 ->
        {los, k} = Refine.bisect(ctx, t - step, t)

        close(station, acc, sat, open, los, k)
        |> then(&{{station, nil, v}, &1})

      true ->
        {{station, open, v}, acc}
    end
  end

  # A pass still open at the end of the grid is traced on to its LOS.
  defp finish({_station, nil, _v}, acc, _sat, _t_end, _step, _bound), do: acc
  defp finish({_station, :unbracketed, _v}, acc, _sat, _t_end, _step, _bound), do: acc

  defp finish({station, aos, _v}, acc, sat, t_end, step, bound) do
    case Refine.lead_out({sat, station}, t_end, step, bound) do
      {:ok, los, k} ->
        close(station, acc, sat, aos, los, k)

      {:unbracketed, k} ->
        %{acc | calls: acc.calls + k, found: [unbracketed(sat, station, t_end) | acc.found]}
    end
  end

  defp close(station, acc, sat, aos, los, k) do
    ctx = {sat, station}
    {tca, k2} = Refine.golden(ctx, aos, los)
    {aos_az, _} = Station.look_angles(station, Refine.ecef(sat, aos))
    {_, max_el} = Station.look_angles(station, Refine.ecef(sat, tca))
    {los_az, _} = Station.look_angles(station, Refine.ecef(sat, los))

    pass = %Pass{
      station_id: station.id,
      aos: at(sat, aos),
      tca: at(sat, tca),
      los: at(sat, los),
      max_elevation_deg: max_el,
      aos_azimuth_deg: aos_az,
      los_azimuth_deg: los_az
    }

    %{acc | calls: acc.calls + k + k2 + 3, found: [pass | acc.found]}
  end

  defp unbracketed(sat, station, t),
    do: {:error, :pass_not_bracketed, %{station_id: station.id, near: at(sat, t)}}

  defp minutes(%Satellite{epoch: epoch}, datetime),
    do: DateTime.diff(datetime, epoch, :microsecond) / 60_000_000

  # The instant `t` minutes after the epoch, to the second.
  defp at(%Satellite{epoch: epoch}, t) do
    microseconds = DateTime.to_unix(epoch, :microsecond) + round(t * 60_000_000)
    DateTime.from_unix!(div(microseconds + 500_000, 1_000_000))
  end
end
