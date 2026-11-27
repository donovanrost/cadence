defmodule Cadence.GroundNetworks.ElementSets.Tle do
  @moduledoc """
  Parses a two-line element set, with or without its title line (#889).

  Each element line is 69 columns: the line number, the catalog number (digits, or Alpha-5 for
  catalog numbers above 99,999), the fields at their fixed columns, and a mod-10 checksum in
  column 69 (digits count their value, `-` counts 1). Eccentricity has an implied leading decimal
  point; ṅ/2 has an implied leading zero; n̈/6 and B* are an implied-decimal mantissa with a
  power-of-ten exponent (` 12345-4` is 0.12345e-4).

  The stored text is the lines with trailing whitespace removed, joined by `\\n`, so the same set
  sent with CRLF line ends or trailing blanks is the same set.
  """

  alias Cadence.GroundNetworks.ElementSets.Elements

  # Alpha-5 skips I and O, which read as 1 and 0.
  @alpha5 ~c"ABCDEFGHJKLMNPQRSTUVWXYZ"

  @spec parse(binary()) :: {:ok, Elements.t()} | Elements.refusal()
  def parse(text) when is_binary(text) do
    with {:ok, name, line1, line2} <- split(text),
         :ok <- line(line1, "1", 1),
         :ok <- line(line2, "2", 2),
         {:ok, catalog} <- catalog(line1, line2),
         {:ok, fields} <- fields(line1, line2) do
      raw = Enum.join(Enum.reject([name, line1, line2], &is_nil/1), "\n")

      {:ok,
       struct!(
         Elements,
         Map.merge(fields, %{format: :tle, raw: raw, object_name: title(name), norad_id: catalog})
       )}
    end
  end

  def parse(_text), do: unparseable("tle", "must be text")

  defp split(text) do
    lines =
      text
      |> String.split(["\r\n", "\n", "\r"])
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [line1, line2] -> {:ok, nil, line1, line2}
      [name, line1, line2] -> {:ok, name, line1, line2}
      _other -> unparseable("tle", "must be two element lines, optionally after a title line")
    end
  end

  defp title(nil), do: nil
  defp title("0 " <> name), do: String.trim(name)
  defp title(name), do: String.trim(name)

  defp line(text, number, index) do
    cond do
      byte_size(text) != 69 or not String.printable?(text) ->
        unparseable("line#{index}", "must be 69 characters")

      binary_part(text, 0, 2) != number <> " " ->
        unparseable("line#{index}", "must start with #{number}")

      checksum(binary_part(text, 0, 68)) != digit(binary_part(text, 68, 1)) ->
        {:error,
         {:bad_checksum, %{field: "line#{index}", expected: checksum(binary_part(text, 0, 68))}}}

      true ->
        :ok
    end
  end

  defp checksum(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(0, fn
      char, sum when char in ?0..?9 -> sum + char - ?0
      ?-, sum -> sum + 1
      _char, sum -> sum
    end)
    |> rem(10)
  end

  defp digit(<<char>>) when char in ?0..?9, do: char - ?0
  defp digit(_other), do: nil

  defp catalog(line1, line2) do
    with {:ok, first} <- catalog_number(column(line1, 3, 7)),
         {:ok, second} <- catalog_number(column(line2, 3, 7)) do
      if first == second,
        do: {:ok, first},
        else: {:error, {:catalog_number_mismatch, %{field: "line2", line1: first, line2: second}}}
    end
  end

  defp catalog_number(<<letter, rest::binary-size(4)>> = text) do
    cond do
      letter in ?0..?9 ->
        integer(String.trim(text), "catalog_number")

      index = Enum.find_index(@alpha5, &(&1 == letter)) ->
        with {:ok, low} <- integer(rest, "catalog_number"), do: {:ok, (10 + index) * 10_000 + low}

      true ->
        unparseable("catalog_number", "must be digits or Alpha-5")
    end
  end

  defp catalog_number(_text), do: unparseable("catalog_number", "must be 5 characters")

  defp fields(line1, line2) do
    with {:ok, epoch} <- epoch(column(line1, 19, 20), column(line1, 21, 32)),
         {:ok, ndot} <- decimal(column(line1, 34, 43), "mean_motion_dot"),
         {:ok, nddot} <- exponent(column(line1, 45, 52), "mean_motion_ddot"),
         {:ok, bstar} <- exponent(column(line1, 54, 61), "bstar"),
         {:ok, set} <- integer(String.trim(column(line1, 65, 68)), "element_set_number"),
         {:ok, inclination} <- decimal(column(line2, 9, 16), "inclination"),
         {:ok, raan} <- decimal(column(line2, 18, 25), "raan"),
         {:ok, eccentricity} <- decimal("0." <> column(line2, 27, 33), "eccentricity"),
         {:ok, argp} <- decimal(column(line2, 35, 42), "arg_perigee"),
         {:ok, anomaly} <- decimal(column(line2, 44, 51), "mean_anomaly"),
         {:ok, motion} <- decimal(column(line2, 53, 63), "mean_motion") do
      {:ok,
       %{
         epoch: epoch,
         mean_motion_dot: ndot,
         mean_motion_ddot: nddot,
         bstar: bstar,
         element_set_number: set,
         inclination_deg: inclination,
         raan_deg: raan,
         eccentricity: eccentricity,
         arg_perigee_deg: argp,
         mean_anomaly_deg: anomaly,
         mean_motion: motion
       }}
    end
  end

  # 1-indexed inclusive columns, as the format is documented.
  defp column(line, from, to), do: binary_part(line, from - 1, to - from + 1)

  # Two-digit years: 57–99 are 1957–1999, 00–56 are 2000–2056. The day fraction is read as an
  # exact integer so the epoch is the same microsecond on every parse.
  defp epoch(year_text, day_text) do
    with {:ok, yy} <- integer(year_text, "epoch"),
         [_, day, fraction] <- Regex.run(~r/^\s*(\d{1,3})\.(\d{1,8})$/, day_text),
         day = String.to_integer(day),
         true <- day in 1..366 do
      year = if yy < 57, do: 2000 + yy, else: 1900 + yy
      scale = Integer.pow(10, String.length(fraction))
      micros = div(String.to_integer(fraction) * 86_400_000_000 + div(scale, 2), scale)

      epoch =
        Date.new!(year, 1, 1)
        |> Date.add(day - 1)
        |> DateTime.new!(~T[00:00:00.000000], "Etc/UTC")
        |> DateTime.add(micros, :microsecond)

      if epoch.year == year,
        do: {:ok, epoch},
        else: unparseable("epoch", "day of year is past the end of #{year}")
    else
      {:error, _reason} = error -> error
      _other -> unparseable("epoch", "must be a day of year from 1 to 366 with its fraction")
    end
  end

  defp integer(text, field) do
    case Integer.parse(text) do
      {value, ""} when value >= 0 -> {:ok, value}
      _other -> unparseable(field, "must be a whole number")
    end
  end

  # " -.00002182", " 51.6416", "0.0006703": an optional sign, an optional leading zero.
  defp decimal(text, field) do
    text = String.trim(text)

    normalized =
      case text do
        "-." <> rest -> "-0." <> rest
        "+." <> rest -> "0." <> rest
        "." <> rest -> "0." <> rest
        "+" <> rest -> rest
        other -> other
      end

    case Float.parse(normalized) do
      {value, ""} -> {:ok, value}
      _other -> unparseable(field, "must be a number")
    end
  end

  # " 12345-4" → 0.12345e-4; "-11606-4" → -0.11606e-4; " 00000-0" and " 00000+0" → 0.0.
  defp exponent(text, field) do
    case Regex.run(~r/^\s*([+-]?)(\d{1,5})([+-])(\d)$/, text) do
      [_, sign, mantissa, exp_sign, exp] ->
        value = String.to_integer(mantissa) / :math.pow(10, String.length(mantissa))
        power = if exp_sign == "-", do: -String.to_integer(exp), else: String.to_integer(exp)
        value = value * :math.pow(10, power)
        {:ok, if(sign == "-", do: -value, else: value)}

      nil ->
        unparseable(field, "must be an implied-decimal mantissa and exponent")
    end
  end

  defp unparseable(field, message),
    do: {:error, {:unparseable, %{field: field, message: message}}}
end
