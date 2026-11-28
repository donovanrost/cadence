defmodule Sgp4Test do
  use ExUnit.Case, async: true

  alias Sgp4.{Satellite, Station}

  @iss %{
    epoch: ~U[2008-09-20 12:25:40.104192Z],
    mean_motion: 15.72125391,
    eccentricity: 0.0006703,
    inclination_deg: 51.6416,
    raan_deg: 247.4627,
    arg_perigee_deg: 130.536,
    mean_anomaly_deg: 325.0288,
    bstar: -1.1606e-5
  }

  test "initializes a near-earth set and propagates it to about its orbital radius" do
    assert {:ok, %Satellite{} = sat} = Sgp4.init(Map.put(@iss, :object_name, "ISS (ZARYA)"))
    assert_in_delta Satellite.period_min(sat), 91.6, 0.1
    assert {:ok, {x, y, z}, {vx, vy, vz}} = Sgp4.propagate(sat, 45)
    assert_in_delta :math.sqrt(x * x + y * y + z * z), 6720.0, 30.0
    assert_in_delta :math.sqrt(vx * vx + vy * vy + vz * vz), 7.7, 0.1
  end

  test "refuses deep space, non-physical and malformed elements" do
    assert {:error, :deep_space_not_supported} = Sgp4.init(%{@iss | mean_motion: 6.0})
    assert {:error, :mean_motion_not_positive} = Sgp4.init(%{@iss | mean_motion: 0})
    assert {:error, :mean_elements_out_of_range} = Sgp4.init(%{@iss | eccentricity: 1.0})
    assert {:error, :mean_elements_out_of_range} = Sgp4.init(%{@iss | eccentricity: -0.1})
    assert {:error, :invalid_elements} = Sgp4.init(Map.delete(@iss, :epoch))
  end

  test "a station validates its coordinates and mask" do
    assert {:ok, %Station{mask_deg: 5.0}} = Station.new(:svalbard, 78.23, 15.39, 450, 5)
    assert {:error, :latitude_out_of_range} = Station.new(:x, 91, 0, 0, 5)
    assert {:error, :longitude_out_of_range} = Station.new(:x, 0, 181, 0, 5)
    assert {:error, :mask_out_of_range} = Station.new(:x, 0, 0, 0, 90)
    assert {:error, :mask_out_of_range} = Station.new(:x, 0, 0, 0, -1)
    assert {:error, :invalid_station} = Station.new(:x, "0", 0, 0, 5)
  end

  test "a station sits on the WGS84 ellipsoid and looks along its local vertical" do
    {:ok, pole} = Station.new(:pole, 90.0, 0.0, 0.0, 0.0)
    {_x, _y, z} = pole.ecef
    assert_in_delta z, 6356.752, 0.001

    {:ok, equator} = Station.new(:eq, 0.0, 0.0, 0.0, 0.0)
    assert_in_delta elem(equator.ecef, 0), 6378.137, 1.0e-9
    assert {azimuth, elevation} = Station.look_angles(equator, {7000.0, 0.0, 0.0})
    assert_in_delta elevation, 90.0, 1.0e-9
    assert is_float(azimuth)
    assert {_az, el} = Station.look_angles(equator, {6378.137, 100.0, 0.0})
    assert_in_delta el, 0.0, 1.0e-9
  end
end
