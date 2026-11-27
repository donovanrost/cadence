defmodule Sgp4.Station do
  @moduledoc """
  A ground station on the WGS84 ellipsoid: geodetic latitude and longitude (degrees), height
  above the ellipsoid (metres) and an elevation mask (degrees). `new/5` precomputes its
  earth-fixed position and its local east, north and up, so look angles cost a few
  multiplications per spacecraft position.

  The ellipsoid is WGS84 because station coordinates are surveyed in it; SGP4 itself stays on
  WGS72 (`Sgp4.Constants`).
  """

  @a_km 6378.137
  @f 1.0 / 298.257223563
  @e2 @f * (2.0 - @f)
  @deg :math.pi() / 180.0

  @enforce_keys [:id, :latitude_deg, :longitude_deg, :height_m, :mask_deg]
  defstruct [
    :id,
    :latitude_deg,
    :longitude_deg,
    :height_m,
    :mask_deg,
    :ecef,
    :east,
    :north,
    :up,
    :sin_mask
  ]

  @type vector :: {float(), float(), float()}
  @type t :: %__MODULE__{
          id: term(),
          latitude_deg: float(),
          longitude_deg: float(),
          height_m: float(),
          mask_deg: float(),
          ecef: vector(),
          east: vector(),
          north: vector(),
          up: vector(),
          sin_mask: float()
        }

  @doc """
  A station. `id` is the caller's (it is carried onto each pass). Latitude must be within
  [−90, 90], longitude within [−180, 180] and the mask within [0, 90).
  """
  @spec new(term(), number(), number(), number(), number()) :: {:ok, t()} | {:error, atom()}
  def new(id, latitude_deg, longitude_deg, height_m, mask_deg)
      when is_number(latitude_deg) and is_number(longitude_deg) and is_number(height_m) and
             is_number(mask_deg) do
    with :ok <- range(latitude_deg, -90, 90, :latitude_out_of_range),
         :ok <- range(longitude_deg, -180, 180, :longitude_out_of_range),
         :ok <- mask(mask_deg) do
      {:ok, build(id, latitude_deg * 1.0, longitude_deg * 1.0, height_m * 1.0, mask_deg * 1.0)}
    end
  end

  def new(_id, _latitude, _longitude, _height, _mask), do: {:error, :invalid_station}

  defp range(value, min, max, _error) when value >= min and value <= max, do: :ok
  defp range(_value, _min, _max, error), do: {:error, error}

  defp mask(mask_deg) when mask_deg >= 0 and mask_deg < 90, do: :ok
  defp mask(_mask_deg), do: {:error, :mask_out_of_range}

  defp build(id, lat_deg, lon_deg, height_m, mask_deg) do
    lat = lat_deg * @deg
    lon = lon_deg * @deg
    {sin_lat, cos_lat} = {:math.sin(lat), :math.cos(lat)}
    {sin_lon, cos_lon} = {:math.sin(lon), :math.cos(lon)}
    n = @a_km / :math.sqrt(1.0 - @e2 * sin_lat * sin_lat)
    h = height_m / 1000.0

    %__MODULE__{
      id: id,
      latitude_deg: lat_deg,
      longitude_deg: lon_deg,
      height_m: height_m,
      mask_deg: mask_deg,
      ecef:
        {(n + h) * cos_lat * cos_lon, (n + h) * cos_lat * sin_lon,
         (n * (1.0 - @e2) + h) * sin_lat},
      east: {-sin_lon, cos_lon, 0.0},
      north: {-sin_lat * cos_lon, -sin_lat * sin_lon, cos_lat},
      up: {cos_lat * cos_lon, cos_lat * sin_lon, sin_lat},
      sin_mask: :math.sin(mask_deg * @deg)
    }
  end

  @doc "sin(elevation) − sin(mask) of an earth-fixed position (km): positive above the mask."
  @spec above_mask(t(), vector()) :: float()
  def above_mask(%__MODULE__{ecef: {sx, sy, sz}, up: {ux, uy, uz}, sin_mask: sin_mask}, {x, y, z}) do
    dx = x - sx
    dy = y - sy
    dz = z - sz
    (dx * ux + dy * uy + dz * uz) / :math.sqrt(dx * dx + dy * dy + dz * dz) - sin_mask
  end

  @doc "Azimuth (degrees from north through east, [0, 360)) and elevation (degrees)."
  @spec look_angles(t(), vector()) :: {float(), float()}
  def look_angles(%__MODULE__{ecef: {sx, sy, sz}} = station, {x, y, z}) do
    d = {x - sx, y - sy, z - sz}
    range = :math.sqrt(dot(d, d))
    elevation = :math.asin(dot(d, station.up) / range) / @deg
    azimuth = :math.atan2(dot(d, station.east), dot(d, station.north)) / @deg
    {if(azimuth < 0.0, do: azimuth + 360.0, else: azimuth), elevation}
  end

  defp dot({a, b, c}, {x, y, z}), do: a * x + b * y + c * z
end
