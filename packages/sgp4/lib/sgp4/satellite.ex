defmodule Sgp4.Satellite do
  @moduledoc """
  An element set initialized for near-earth SGP4: the mean elements in radians and rad/min (the
  mean motion un-Kozai'd), plus the coefficients `Sgp4.Init` derives once so that each
  propagation is a fixed amount of arithmetic.

  Build one with `Sgp4.init/1`; the fields are internal to the propagator.
  """

  @enforce_keys [:epoch, :jd_epoch, :gmst_epoch, :no, :ecco, :inclo, :isimp, :coefficients]
  defstruct [:epoch, :jd_epoch, :gmst_epoch, :no, :ecco, :inclo, :isimp, :coefficients]

  # The coefficients, in the order `Sgp4.Propagator` matches them: one tuple, so a propagation
  # reads them in a single match.
  @coefficients [
    :nodeo,
    :argpo,
    :mo,
    :bstar,
    :mdot,
    :argpdot,
    :nodedot,
    :nodecf,
    :cc1,
    :cc4,
    :cc5,
    :t2cof,
    :omgcof,
    :xmcof,
    :eta,
    :delmo,
    :sinmao,
    :d2,
    :d3,
    :d4,
    :t3cof,
    :t4cof,
    :t5cof,
    :aycof,
    :xlcof,
    :con41,
    :x1mth2,
    :x7thm1,
    :sinio,
    :cosio
  ]

  @doc false
  def coefficient_names, do: @coefficients

  @type t :: %__MODULE__{}

  @doc "The orbital period in minutes, from the un-Kozai'd mean motion."
  @spec period_min(t()) :: float()
  def period_min(%__MODULE__{no: no}), do: 2.0 * :math.pi() / no
end
