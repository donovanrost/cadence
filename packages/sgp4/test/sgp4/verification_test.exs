defmodule Sgp4.VerificationTest do
  @moduledoc """
  Vallado's full verification set (AIAA 2006-6753): every near-earth case is propagated to every
  reference time and compared in position and velocity; every deep-space case is refused; and
  the near-earth cases that decay fail at the step after the reference's last row, as Vallado's
  driver stops there.
  """

  use ExUnit.Case, async: true

  alias Sgp4.Test.Vallado

  # The reference prints positions to 1e-8 km and velocities to 1e-9 km/s, and this port lands
  # within rounding of those digits (worst 0.007 mm and 0.8e-9 km/s over the set). The bounds
  # leave ten times that for another platform's libm, still far inside SGP4's own error (~1 km).
  @position_tolerance_km 1.0e-7
  @velocity_tolerance_km_s 1.0e-8

  @cases Vallado.cases()
  @reference Map.new(Vallado.reference())

  # A case's reference rows run while Vallado's driver saw no error; these three then fail at the
  # next step with Vallado's code 1 (mean eccentricity out of range) or 6 (decayed).
  @decaying %{
    22_312 => {494.2028672, :mean_elements_out_of_range},
    28_872 => {55.0, :decayed},
    29_141 => {440.0, :decayed}
  }

  test "the set is complete: 33 cases, each with reference rows" do
    assert length(@cases) == 33
    assert length(Vallado.reference()) == 33
  end

  test "every near-earth case matches the reference at every reference time" do
    near = Enum.filter(@cases, &near_earth?/1)

    assert Enum.map(near, & &1.id) == [
             5,
             6251,
             22_312,
             28_057,
             28_350,
             28_872,
             29_141,
             29_238,
             88_888
           ]

    compared =
      near
      |> Enum.flat_map(fn c ->
        rows = Map.fetch!(@reference, c.id)
        {:ok, sat} = Sgp4.init(c.elements)

        Enum.map(rows, fn {t, position, velocity} ->
          assert {:ok, p, v} = Sgp4.propagate(sat, t), "case #{c.id} at #{t} min"
          dp = distance(p, position)
          dv = distance(v, velocity)

          assert dp <= @position_tolerance_km,
                 "case #{c.id} at #{t} min: position off by #{dp * 1.0e6} mm"

          assert dv <= @velocity_tolerance_km_s,
                 "case #{c.id} at #{t} min: velocity off by #{dv * 1.0e6} mm/s"

          {dp, dv}
        end)
      end)

    assert length(compared) == Enum.sum(Enum.map(near, &length(Map.fetch!(@reference, &1.id))))
  end

  test "the decaying near-earth cases fail at the step after the reference's last row" do
    for {id, {t, reason}} <- @decaying do
      c = Enum.find(@cases, &(&1.id == id))
      {:ok, sat} = Sgp4.init(c.elements)
      {last, _p, _v} = List.last(Map.fetch!(@reference, id))
      assert {:ok, _, _} = Sgp4.propagate(sat, last)
      assert {:error, ^reason} = Sgp4.propagate(sat, t), "case #{id} at #{t} min"
    end
  end

  test "every deep-space case is refused" do
    deep = Enum.reject(@cases, &near_earth?/1)
    assert length(deep) == 24

    for c <- deep,
        do: assert({:error, :deep_space_not_supported} = Sgp4.init(c.elements), "case #{c.id}")
  end

  # Near earth: a period under 225 minutes from the TLE's (Kozai) mean motion. Only the cases
  # near the boundary would differ un-Kozai'd, and the set has none there.
  defp near_earth?(c), do: 1440.0 / c.elements.mean_motion < 225.0

  defp distance({ax, ay, az}, {bx, by, bz}),
    do: :math.sqrt((ax - bx) ** 2 + (ay - by) ** 2 + (az - bz) ** 2)
end
