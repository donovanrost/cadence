defmodule Cadence.GroundNetworks.ElementSets.Elements do
  @moduledoc """
  One parsed set of SGP4 mean elements (#889), from a TLE or an OMM, before it is stored.

  Angles are degrees, mean motion is revolutions per day (Kozai, as both formats carry it for
  SGP4), `mean_motion_dot` is ṅ/2 in rev/day² and `mean_motion_ddot` is n̈/6 in rev/day³, `bstar` is
  in inverse Earth radii. `raw` is the text as stored and hashed.

  `validate/2` refuses a non-physical set and an epoch more than a day ahead of `now`. Each
  refusal is `{:error, {reason, details}}` with a stable reason the REST API answers with.
  """

  @enforce_keys [:format, :raw, :epoch, :mean_motion, :eccentricity, :inclination_deg]
  defstruct [
    :format,
    :raw,
    :object_name,
    :norad_id,
    :element_set_number,
    :epoch,
    :mean_motion,
    :eccentricity,
    :inclination_deg,
    :raan_deg,
    :arg_perigee_deg,
    :mean_anomaly_deg,
    :bstar,
    :mean_motion_dot,
    :mean_motion_ddot
  ]

  @type format :: :tle | :omm
  @type t :: %__MODULE__{
          format: format(),
          raw: binary(),
          object_name: binary() | nil,
          norad_id: non_neg_integer() | nil,
          element_set_number: non_neg_integer() | nil,
          epoch: DateTime.t(),
          mean_motion: float(),
          eccentricity: float(),
          inclination_deg: float(),
          raan_deg: float(),
          arg_perigee_deg: float(),
          mean_anomaly_deg: float(),
          bstar: float(),
          mean_motion_dot: float(),
          mean_motion_ddot: float()
        }

  @type refusal :: {:error, {atom(), map()}}

  # An epoch this far ahead of the server clock is a typo or a wrong year, not a prediction.
  @future_limit_seconds 86_400

  @angles [
    raan_deg: 360.0,
    arg_perigee_deg: 360.0,
    mean_anomaly_deg: 360.0
  ]

  @doc "Refuses a non-physical element set, or one whose epoch is more than a day after `now`."
  @spec validate(t(), DateTime.t()) :: {:ok, t()} | refusal()
  def validate(%__MODULE__{} = elements, %DateTime{} = now) do
    with :ok <- physical(elements),
         :ok <- epoch(elements.epoch, now),
         do: {:ok, elements}
  end

  @doc "The SHA-256 of the stored text, lowercase hex: half of the natural key."
  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{raw: raw}),
    do: :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower)

  defp physical(%__MODULE__{} = e) do
    cond do
      not (e.eccentricity >= 0.0 and e.eccentricity < 1.0) ->
        non_physical("eccentricity", "must be at least 0 and less than 1")

      not (e.mean_motion > 0.0) ->
        non_physical("mean_motion", "must be greater than 0")

      not (e.inclination_deg >= 0.0 and e.inclination_deg <= 180.0) ->
        non_physical("inclination", "must be between 0 and 180 degrees")

      field = Enum.find(@angles, fn {key, max} -> out_of_range?(Map.fetch!(e, key), max) end) ->
        {key, _max} = field

        non_physical(
          key |> Atom.to_string() |> String.replace_suffix("_deg", ""),
          "must be between 0 and 360 degrees"
        )

      true ->
        :ok
    end
  end

  defp out_of_range?(value, max), do: not (value >= 0.0 and value <= max)

  defp non_physical(field, message),
    do: {:error, {:non_physical, %{field: field, message: message}}}

  defp epoch(epoch, now) do
    if DateTime.diff(epoch, now, :microsecond) > @future_limit_seconds * 1_000_000,
      do: {:error, {:epoch_in_future, %{epoch: DateTime.to_iso8601(epoch)}}},
      else: :ok
  end
end
