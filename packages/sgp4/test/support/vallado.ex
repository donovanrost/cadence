defmodule Sgp4.Test.Vallado do
  @moduledoc """
  Reads Vallado's verification set (test/fixtures): the element sets in `SGP4-VER.TLE`, with
  each case's start, stop and step in minutes after line 2, and the reference positions and
  velocities in `tmatverDec2015.out` (Vallado's MATLAB run of the same set, which agrees with the
  C++ `tcppver.out` to well under a millimetre). Both files are data from CelesTrak's archive of
  AIAA 2006-6753; this module only parses them.
  """

  @fixtures Path.expand("../fixtures", __DIR__)

  @doc "Every case: `%{id, elements, start, stop, step}` in file order."
  def cases do
    @fixtures
    |> Path.join("SGP4-VER.TLE")
    |> File.read!()
    |> String.split(["\r\n", "\n"])
    |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
    |> Enum.chunk_every(2)
    |> Enum.map(fn [line1, line2] -> case_of(line1, line2) end)
  end

  @doc "The reference rows of each case, in order: `%{id => [{t, position, velocity}]}`."
  def reference do
    @fixtures
    |> Path.join("tmatverDec2015.out")
    |> File.read!()
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.reduce({nil, []}, fn line, {id, acc} ->
      case String.split(line) do
        [case_id, "xx"] -> {String.to_integer(case_id), acc}
        [t, x, y, z, vx, vy, vz | _] -> {id, [{id, row(t, {x, y, z}, {vx, vy, vz})} | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{id, _} | _] = rows -> {id, Enum.map(rows, &elem(&1, 1))} end)
  end

  defp row(t, {x, y, z}, {vx, vy, vz}),
    do: {float(t), {float(x), float(y), float(z)}, {float(vx), float(vy), float(vz)}}

  defp case_of(line1, line2) do
    [start, stop, step] = line2 |> binary_part(69, byte_size(line2) - 69) |> String.split()

    %{
      id: line1 |> binary_part(2, 5) |> String.trim() |> String.to_integer(),
      start: float(start),
      stop: float(stop),
      step: float(step),
      elements: %{
        epoch: epoch(binary_part(line1, 18, 14)),
        bstar: exponent(binary_part(line1, 53, 8)),
        inclination_deg: field(line2, 8, 8),
        raan_deg: field(line2, 17, 8),
        eccentricity: float("0." <> binary_part(line2, 26, 7)),
        arg_perigee_deg: field(line2, 34, 8),
        mean_anomaly_deg: field(line2, 43, 8),
        mean_motion: field(line2, 52, 11)
      }
    }
  end

  defp field(line, at, size), do: line |> binary_part(at, size) |> float()

  # " 28098-4" is 0.28098e-4; "-11606-4" is -0.11606e-4.
  defp exponent(text) do
    text = String.trim(text)

    {sign, digits} =
      if String.starts_with?(text, "-"),
        do: {-1.0, String.slice(text, 1..-1//1)},
        else: {1.0, String.trim_leading(text, "+")}

    {mantissa, power} = String.split_at(digits, -2)
    sign * float("0." <> mantissa) * :math.pow(10, String.to_integer(power))
  end

  defp epoch(text) do
    {yy, day} = text |> String.trim() |> String.split_at(2)
    yy = String.to_integer(yy)
    year = if yy < 57, do: 2000 + yy, else: 1900 + yy
    {:ok, start} = DateTime.new(Date.new!(year, 1, 1), ~T[00:00:00.000000], "Etc/UTC")
    DateTime.add(start, round((float(day) - 1.0) * 86_400_000_000), :microsecond)
  end

  defp float(text) do
    text = String.trim(text)
    text = if String.starts_with?(text, "."), do: "0" <> text, else: text

    text =
      if String.starts_with?(text, "-."), do: "-0" <> String.slice(text, 1..-1//1), else: text

    case Float.parse(text) do
      {value, ""} -> value
      _other -> text |> String.to_integer() |> Kernel.*(1.0)
    end
  end
end
