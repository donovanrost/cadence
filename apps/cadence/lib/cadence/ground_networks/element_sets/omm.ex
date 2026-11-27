defmodule Cadence.GroundNetworks.ElementSets.Omm do
  @moduledoc """
  Parses a CCSDS Orbit Mean-Elements Message (#889) as JSON (an object, as CelesTrak and
  Space-Track emit it, with numbers or numeric strings) or as KVN text (`KEY = value` lines,
  `COMMENT` lines and units in brackets ignored).

  Only SGP4 mean elements are accepted: a `MEAN_ELEMENT_THEORY` other than SGP4 is refused, since
  the elements would mean something else. `MEAN_MOTION_DOT` and `MEAN_MOTION_DDOT` default to 0
  (SGP4 doesn't use them); `BSTAR` is required.

  The stored text of a JSON OMM is the object re-encoded with its keys sorted; of a KVN OMM, its
  non-blank lines with trailing whitespace removed. Either way the same message hashes the same.
  """

  alias Cadence.GroundNetworks.ElementSets.Elements

  @required [
    {"EPOCH", :epoch},
    {"MEAN_MOTION", :mean_motion},
    {"ECCENTRICITY", :eccentricity},
    {"INCLINATION", :inclination_deg},
    {"RA_OF_ASC_NODE", :raan_deg},
    {"ARG_OF_PERICENTER", :arg_perigee_deg},
    {"MEAN_ANOMALY", :mean_anomaly_deg},
    {"BSTAR", :bstar}
  ]

  @optional_rates [{"MEAN_MOTION_DOT", :mean_motion_dot}, {"MEAN_MOTION_DDOT", :mean_motion_ddot}]
  @sgp4_theories ["SGP4", "SGP/SGP4"]

  @spec parse(map() | binary()) :: {:ok, Elements.t()} | Elements.refusal()
  def parse(%{} = object) when not is_struct(object) do
    with {:ok, fields} <- string_fields(object), do: build(fields, json_raw(object))
  end

  def parse(text) when is_binary(text) do
    with {:ok, fields, lines} <- kvn(text), do: build(fields, Enum.join(lines, "\n"))
  end

  def parse(_other), do: unparseable("omm", "must be a JSON object or KVN text")

  defp string_fields(object) do
    Enum.reduce_while(object, {:ok, %{}}, fn
      {key, value}, {:ok, acc} when is_binary(key) and (is_binary(value) or is_number(value)) ->
        {:cont, {:ok, Map.put(acc, String.upcase(key), value)}}

      {_key, nil}, acc ->
        {:cont, acc}

      {key, _value}, _acc ->
        {:halt, unparseable(to_string(key), "must be a string or a number")}
    end)
  end

  defp json_raw(object) do
    object
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Jason.OrderedObject.new()
    |> Jason.encode!()
  end

  defp kvn(text) do
    lines =
      text
      |> String.split(["\r\n", "\n", "\r"])
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(String.trim(&1) == ""))

    lines
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "COMMENT"))
    |> Enum.reduce_while({:ok, %{}}, fn line, {:ok, acc} ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          {:cont, {:ok, Map.put(acc, String.trim(key) |> String.upcase(), strip_units(value))}}

        _other ->
          {:halt, unparseable("omm", "line #{inspect(String.slice(line, 0, 40))} has no =")}
      end
    end)
    |> case do
      {:ok, fields} when map_size(fields) == 0 -> unparseable("omm", "is empty")
      {:ok, fields} -> {:ok, fields, lines}
      error -> error
    end
  end

  defp strip_units(value), do: value |> String.replace(~r/\[[^\]]*\]\s*$/, "") |> String.trim()

  defp build(fields, raw) do
    with :ok <- theory(fields["MEAN_ELEMENT_THEORY"]),
         {:ok, required} <- required(fields),
         {:ok, rates} <- rates(fields),
         {:ok, norad} <- optional_integer(fields, "NORAD_CAT_ID"),
         {:ok, set} <- optional_integer(fields, "ELEMENT_SET_NO") do
      attrs =
        required
        |> Map.merge(rates)
        |> Map.merge(%{
          format: :omm,
          raw: raw,
          object_name: text(fields["OBJECT_NAME"]),
          norad_id: norad,
          element_set_number: set
        })

      {:ok, struct!(Elements, attrs)}
    end
  end

  defp theory(nil), do: :ok

  defp theory(value) do
    if String.upcase(String.trim(to_string(value))) in @sgp4_theories,
      do: :ok,
      else: {:error, {:unsupported_mean_element_theory, %{field: "MEAN_ELEMENT_THEORY"}}}
  end

  defp required(fields) do
    Enum.reduce_while(@required, {:ok, %{}}, fn {key, field}, {:ok, acc} ->
      parsed = if field == :epoch, do: epoch(fields[key]), else: number(fields[key], key)

      case parsed do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp rates(fields) do
    Enum.reduce_while(@optional_rates, {:ok, %{}}, fn {key, field}, {:ok, acc} ->
      case rate(fields[key], key) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp rate(nil, _key), do: {:ok, 0.0}
  defp rate(value, key), do: number(value, key)

  defp number(nil, key), do: unparseable(key, "is required")
  defp number(value, _key) when is_number(value), do: {:ok, value * 1.0}

  defp number(value, key) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _other -> unparseable(key, "must be a number")
    end
  end

  defp optional_integer(fields, key) do
    case fields[key] do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value when is_binary(value) -> parse_integer(String.trim(value), key)
      _other -> unparseable(key, "must be a whole number")
    end
  end

  defp parse_integer(text, key) do
    case Integer.parse(text) do
      {value, ""} when value >= 0 -> {:ok, value}
      _other -> unparseable(key, "must be a whole number")
    end
  end

  defp text(nil), do: nil
  defp text(value), do: value |> to_string() |> String.trim()

  # CCSDS times are UTC: `2008-09-20T12:25:40.104192` or the day-of-year form
  # `2008-264T12:25:40.104192`, with or without a trailing Z.
  defp epoch(nil), do: unparseable("EPOCH", "is required")

  defp epoch(value) when is_binary(value) do
    value = value |> String.trim() |> String.trim_trailing("Z")

    case Regex.run(~r/^(\d{4})-(\d{3})T(.+)$/, value) do
      [_, year, day, time] -> ordinal_epoch(year, day, time)
      nil -> calendar_epoch(value)
    end
  end

  defp epoch(_value), do: unparseable("EPOCH", "must be a UTC time")

  defp calendar_epoch(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, naive |> microseconds() |> DateTime.from_naive!("Etc/UTC")}
      {:error, _reason} -> unparseable("EPOCH", "must be a UTC time")
    end
  end

  defp ordinal_epoch(year, day, time) do
    with {:ok, time} <- Time.from_iso8601(time),
         day = String.to_integer(day),
         true <- day in 1..366,
         date = Date.add(Date.new!(String.to_integer(year), 1, 1), day - 1),
         true <- date.year == String.to_integer(year) do
      {:ok, date |> NaiveDateTime.new!(time) |> microseconds() |> DateTime.from_naive!("Etc/UTC")}
    else
      _invalid -> unparseable("EPOCH", "must be a UTC time")
    end
  end

  defp microseconds(%NaiveDateTime{microsecond: {value, _precision}} = naive),
    do: %{naive | microsecond: {value, 6}}

  defp unparseable(field, message),
    do: {:error, {:unparseable, %{field: field, message: message}}}
end
