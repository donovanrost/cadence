defmodule Sgp4.PassesTest do
  use ExUnit.Case, async: true

  alias Sgp4.{Frames, Passes, Station}
  alias Sgp4.Passes.Refine
  alias Sgp4.Test.Vallado

  @epoch ~U[2026-11-25 00:00:00.000000Z]
  @re 6378.135
  @xke 60.0 / :math.sqrt(6378.135 ** 3 / 398_600.8)

  # A nearly circular equatorial orbit with the given period (minutes), its perigee, node and
  # anomaly at zero, so it is on the TEME x-axis at the epoch.
  defp equatorial(period_min) do
    {:ok, sat} =
      Sgp4.init(%{
        epoch: @epoch,
        mean_motion: 1440.0 / period_min,
        eccentricity: 0.0001,
        inclination_deg: 0.0,
        raan_deg: 0.0,
        arg_perigee_deg: 0.0,
        mean_anomaly_deg: 0.0,
        bstar: 0.0
      })

    sat
  end

  # The equatorial station straight below the TEME x-axis at the epoch.
  defp below(sat, mask_deg \\ 5.0) do
    lon = -sat.gmst_epoch * 180.0 / :math.pi()
    lon = if lon < -180.0, do: lon + 360.0, else: lon
    {:ok, station} = Station.new("gs", 0.0, lon, 0.0, mask_deg)
    station
  end

  defp minutes(datetime), do: DateTime.diff(datetime, @epoch, :microsecond) / 60_000_000
  defp f(sat, station, t), do: Refine.above_mask({sat, station}, t)

  describe "a 220-minute near-earth orbit, whose pass outlasts an hour" do
    test "is found whole from a one-minute window, AOS and LOS at real mask crossings" do
      sat = equatorial(220.0)
      station = below(sat)

      assert {:ok, %{passes: [pass], unbracketed: []}} =
               Passes.search(sat, [station], @epoch, DateTime.add(@epoch, 60), [])

      aos = minutes(pass.aos)
      los = minutes(pass.los)
      assert_in_delta aos, -38.4, 0.2
      assert_in_delta los, 38.4, 0.2
      second = 1.0 / 60.0
      assert f(sat, station, aos - second) < 0 and f(sat, station, aos + second) >= 0
      assert f(sat, station, los - second) >= 0 and f(sat, station, los + second) < 0
      assert pass.max_elevation_deg > 89.0
    end

    test "is unbracketed, never clipped, when the search bound is shorter than the pass" do
      sat = equatorial(220.0)
      ctx = {sat, below(sat)}
      assert {:unbracketed, _} = Refine.lead_in(ctx, 0.0, 1.0, 20.0)
      assert {:unbracketed, _} = Refine.lead_out(ctx, 0.0, 1.0, 20.0)
      assert {:ok, aos, _} = Refine.lead_in(ctx, 0.0, 1.0, Passes.synodic_min(sat))
      assert_in_delta aos, -38.4, 0.2
    end
  end

  describe "a LEO pass straight overhead" do
    setup do
      # 500 km circular: a = re + 500, period from the Kozai mean motion.
      period = 2 * :math.pi() / (@xke / :math.pow((@re + 500.0) / @re, 1.5))
      sat = equatorial(period)
      %{sat: sat, station: below(sat), period: period}
    end

    test "peaks at the zenith at the epoch, and lasts as long as the geometry says", c do
      window = {DateTime.add(@epoch, -1200), DateTime.add(@epoch, 1200)}

      assert {:ok, %{passes: [pass]}} =
               Passes.search(c.sat, [c.station], elem(window, 0), elem(window, 1))

      assert pass.max_elevation_deg > 89.5
      assert abs(minutes(pass.tca)) < 0.1

      # Central angle from zenith to a 5° elevation at 500 km, swept at the rate relative to
      # the rotating earth (prograde equatorial). J2 and the ellipsoid move it by seconds.
      el = 5.0 * :math.pi() / 180.0
      lambda = :math.acos(@re * :math.cos(el) / (@re + 500.0)) - el
      rate = 2 * :math.pi() / c.period - 7.292115146706979e-5 * 60.0
      assert_in_delta minutes(pass.los) - minutes(pass.aos), 2 * lambda / rate, 0.25

      # Rising in the west, setting in the east.
      assert_in_delta pass.aos_azimuth_deg, 270.0, 1.0
      assert_in_delta pass.los_azimuth_deg, 90.0, 1.0
    end

    test "starting inside the window's first minute, is traced back to its real AOS", c do
      assert {:ok, %{passes: [inside]}} =
               Passes.search(c.sat, [c.station], @epoch, DateTime.add(@epoch, 600))

      assert {:ok, %{passes: [whole]}} =
               Passes.search(
                 c.sat,
                 [c.station],
                 DateTime.add(@epoch, -1200),
                 DateTime.add(@epoch, 1200)
               )

      assert minutes(inside.aos) < -3.0
      assert abs(DateTime.diff(inside.aos, whole.aos)) <= 1
      assert abs(DateTime.diff(inside.los, whole.los)) <= 1
    end

    test "one propagation serves every station at each grid point", c do
      # Too far north to ever see an equatorial 500 km orbit.
      {:ok, far} = Station.new("far", 80.0, 0.0, 0.0, 5.0)
      t1 = DateTime.add(@epoch, 3600)
      {:ok, one} = Passes.search(c.sat, [far], @epoch, t1)
      {:ok, two} = Passes.search(c.sat, [far, far], @epoch, t1)
      assert one.passes == [] and two.passes == []
      assert one.propagations == two.propagations
      assert one.propagations == 61
    end
  end

  test "a spacecraft that decays inside the window answers the propagation error" do
    c = Enum.find(Vallado.cases(), &(&1.id == 28_872))
    {:ok, sat} = Sgp4.init(c.elements)
    {:ok, station} = Station.new("gs", 0.0, 0.0, 0.0, 5.0)
    from = sat.epoch

    assert {:error, {:decayed, at}} =
             Passes.search(sat, [station], from, DateTime.add(from, 7200))

    # Vallado's reference has it decayed between 50 and 55 minutes.
    assert DateTime.diff(at, from) in 3000..3300
  end

  test "an empty window or no stations finds nothing" do
    sat = equatorial(95.0)
    {:ok, station} = Station.new("gs", 0.0, 0.0, 0.0, 5.0)
    assert {:ok, %{passes: [], propagations: 0}} = Passes.search(sat, [station], @epoch, @epoch)
    assert {:ok, %{passes: []}} = Passes.search(sat, [], @epoch, DateTime.add(@epoch, 60))
  end

  test "TEME to earth-fixed is a rotation by GMST" do
    gmst = Frames.gmst(Frames.julian_date(@epoch))
    {x, y, z} = Frames.teme_to_ecef({7000.0, 0.0, 10.0}, gmst, 0.0)
    assert_in_delta :math.sqrt(x * x + y * y), 7000.0, 1.0e-9
    assert z == 10.0
    assert_in_delta :math.cos(:math.atan2(y, x) + gmst), 1.0, 1.0e-12
  end
end
