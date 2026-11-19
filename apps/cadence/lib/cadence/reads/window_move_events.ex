defmodule Cadence.Reads.WindowMoveEvents do
  @moduledoc """
  The Timeline sentence for `contact_window_moved` (window truth, director 11-14; words ux U56):
  the provider moved a booked pass and its contact followed. The label uses the NEW AOS; times are
  to the second; the date shows when the new window's day isn't the event's.

    * both ends by the same amount: "EARENDIL-007 · PUQ 13:04Z pass moved 30 s later by Northlight:
      13:04:30–13:12:30Z"
    * one end: "… pass LOS moved 60 s later by Northlight: …" / "… pass AOS moved …"
    * both, by different amounts: "… pass window changed by Northlight: …"

  Without a provider name, "by the provider". Durations: seconds under a minute, else "2 min" or
  "1 min 30 s".
  """

  @spec sentence(map(), binary(), DateTime.t() | nil) :: binary()
  def sentence(doc, craft, occurred_at) do
    after_window = doc["after"] || %{}
    before_window = doc["before"] || %{}
    start_shift = delta(before_window["starts_at"], after_window["starts_at"])
    end_shift = delta(before_window["ends_at"], after_window["ends_at"])
    by = "by #{doc["provider_name"] || "the provider"}"

    "#{label(craft, doc["ground_station_ref"], after_window["starts_at"], occurred_at)} " <>
      "#{change(start_shift, end_shift)} #{by}: #{window(after_window, occurred_at)}"
  end

  defp change(shift, shift) when is_integer(shift) and shift != 0, do: "moved #{amount(shift)}"
  defp change(0, shift) when is_integer(shift) and shift != 0, do: "LOS moved #{amount(shift)}"
  defp change(shift, 0) when is_integer(shift) and shift != 0, do: "AOS moved #{amount(shift)}"
  defp change(_start, _end), do: "window changed"

  defp amount(shift) when shift > 0, do: "#{duration(shift)} later"
  defp amount(shift), do: "#{duration(-shift)} earlier"

  defp duration(seconds) when seconds < 60, do: "#{seconds} s"

  defp duration(seconds) do
    case {div(seconds, 60), rem(seconds, 60)} do
      {minutes, 0} -> "#{minutes} min"
      {minutes, rest} -> "#{minutes} min #{rest} s"
    end
  end

  @doc "\"EARENDIL-007 · PUQ 13:04Z pass\" (the date only when it isn't the event's day)."
  @spec label(binary(), binary() | nil, term(), DateTime.t() | nil) :: binary()
  def label(craft, ref, starts_at, occurred_at) do
    station = if is_binary(ref), do: " · #{ref}", else: ""

    case parse(starts_at) do
      nil -> "#{craft}#{station} pass"
      at -> "#{craft}#{station} #{day(at, occurred_at)}#{clock(at, :minute)} pass"
    end
  end

  # ux U56: the date once when both ends share a day that isn't the event's ("11-15
  # 00:00:00–00:08:00Z"), on both ends across midnight, and not at all on the event's day.
  defp window(%{"starts_at" => from, "ends_at" => to}, occurred_at) do
    case {parse(from), parse(to)} do
      {%DateTime{} = from, %DateTime{} = to} ->
        cond do
          DateTime.to_date(from) != DateTime.to_date(to) ->
            "#{date(from)} #{clock(from, :second)}–#{date(to)} #{clock(to, :second)}Z"

          day(from, occurred_at) == "" ->
            "#{clock(from, :second)}–#{clock(to, :second)}Z"

          true ->
            "#{date(from)} #{clock(from, :second)}–#{clock(to, :second)}Z"
        end

      _unknown ->
        "time unknown"
    end
  end

  defp window(_doc, _occurred_at), do: "time unknown"

  defp date(at), do: Calendar.strftime(at, "%m-%d")

  defp delta(before, after_at) do
    case {parse(before), parse(after_at)} do
      {%DateTime{} = b, %DateTime{} = a} -> DateTime.diff(a, b, :second)
      _unknown -> nil
    end
  end

  # The date only when it isn't the event's day.
  defp day(at, %DateTime{} = occurred_at) do
    if DateTime.to_date(at) == DateTime.to_date(occurred_at),
      do: "",
      else: Calendar.strftime(at, "%m-%d ")
  end

  defp day(_at, _occurred_at), do: ""

  defp clock(at, :minute), do: Calendar.strftime(at, "%H:%MZ")
  defp clock(at, :second), do: Calendar.strftime(at, "%H:%M:%S")

  defp parse(%DateTime{} = at), do: at

  defp parse(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp parse(_other), do: nil
end
