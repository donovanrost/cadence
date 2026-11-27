defmodule Sgp4.Passes.Refine do
  @moduledoc false
  # Refinement for `Sgp4.Passes`, one station at a time. `ctx` is `{satellite, station}`; each
  # function answers its result and the propagations it spent. A propagation error throws
  # `{:sgp4_error, reason, t}`, which `Sgp4.Passes.search/5` catches.

  alias Sgp4.{Frames, Propagator, Station}

  # Bisection and golden section stop at one second.
  @resolution_min 1.0 / 60.0
  @golden 0.6180339887498949

  @doc false
  def ecef(sat, t) do
    case Propagator.propagate(sat, t) do
      {:ok, position, _velocity} -> Frames.teme_to_ecef(position, sat.gmst_epoch, t)
      {:error, reason} -> throw({:sgp4_error, reason, t})
    end
  end

  @doc false
  def above_mask({sat, station}, t), do: Station.above_mask(station, ecef(sat, t))

  @doc """
  The mask crossing in `[a, b]`: bisects to a bracket of one second and answers its midpoint,
  within half a second of the crossing (a second once `Sgp4.Passes` rounds it).
  """
  def bisect(ctx, a, b), do: bisect(ctx, a, b, above_mask(ctx, a), 1)

  defp bisect(ctx, a, b, fa, k) do
    if b - a <= @resolution_min do
      {0.5 * (a + b), k}
    else
      m = 0.5 * (a + b)
      fm = above_mask(ctx, m)
      if fa * fm <= 0, do: bisect(ctx, a, m, fa, k + 1), else: bisect(ctx, m, b, fm, k + 1)
    end
  end

  @doc "The time of maximum elevation in `[a, b]`, by golden section to one second."
  def golden(ctx, a, b) do
    c = b - @golden * (b - a)
    d = a + @golden * (b - a)
    golden(ctx, a, b, {c, above_mask(ctx, c)}, {d, above_mask(ctx, d)}, 2)
  end

  defp golden(ctx, a, b, {c, fc}, {d, fd}, k) do
    cond do
      b - a <= @resolution_min ->
        {0.5 * (a + b), k}

      fc > fd ->
        c2 = d - @golden * (d - a)
        golden(ctx, a, d, {c2, above_mask(ctx, c2)}, {c, fc}, k + 1)

      true ->
        d2 = c + @golden * (b - c)
        golden(ctx, c, b, {d, fd}, {d2, above_mask(ctx, d2)}, k + 1)
    end
  end

  @doc """
  Above the mask at `t0`: steps back until below it, at most `bound` minutes, then bisects to
  the AOS. `{:ok, aos, k}` or `{:unbracketed, k}`; the bound is never taken as an AOS.
  """
  def lead_in(ctx, t0, step, bound), do: lead_in(ctx, t0, t0 - step, step, bound, 0)

  defp lead_in(ctx, t0, t, step, bound, k) do
    cond do
      above_mask(ctx, t) < 0 ->
        {aos, k2} = bisect(ctx, t, t + step)
        {:ok, aos, k + 1 + k2}

      t <= t0 - bound ->
        {:unbracketed, k + 1}

      true ->
        lead_in(ctx, t0, t - step, step, bound, k + 1)
    end
  end

  @doc """
  Still above the mask at `t_end`: steps on until below it, at most `bound` minutes, then
  bisects to the LOS. `{:ok, los, k}` or `{:unbracketed, k}`.
  """
  def lead_out(ctx, t_end, step, bound), do: lead_out(ctx, t_end, t_end + step, step, bound, 0)

  defp lead_out(ctx, t_end, t, step, bound, k) do
    cond do
      above_mask(ctx, t) < 0 ->
        {los, k2} = bisect(ctx, t - step, t)
        {:ok, los, k + 1 + k2}

      t >= t_end + bound ->
        {:unbracketed, k + 1}

      true ->
        lead_out(ctx, t_end, t + step, step, bound, k + 1)
    end
  end
end
