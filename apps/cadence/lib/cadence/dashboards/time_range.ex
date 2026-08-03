defmodule Cadence.Dashboards.TimeRange do
  @moduledoc """
  Grafana-style dashboard time range expressions.

  A time bound is `"now"`, a relative offset such as `"now-6h"`, or an
  absolute ISO-8601 datetime. A `from`/`to` pair resolves to either a
  sliding window (`from: "now-6h", to: "now"`) that follows the current
  time, or a frozen absolute range.
  """

  @unit_seconds %{"s" => 1, "m" => 60, "h" => 3_600, "d" => 86_400, "w" => 604_800}
  @relative_pattern ~r/^now-(\d+)([smhdw])$/

  # Sliding windows drive live-mode backfill on every context change, so the
  # offered window is capped until longer-range backfill cost is measured.
  @max_sliding_window_seconds 86_400

  @quick_ranges [
    %{key: "last_5m", label: "Last 5 minutes", from: "now-5m", to: "now", seconds: 300},
    %{key: "last_15m", label: "Last 15 minutes", from: "now-15m", to: "now", seconds: 900},
    %{key: "last_30m", label: "Last 30 minutes", from: "now-30m", to: "now", seconds: 1_800},
    %{key: "last_1h", label: "Last 1 hour", from: "now-1h", to: "now", seconds: 3_600},
    %{key: "last_3h", label: "Last 3 hours", from: "now-3h", to: "now", seconds: 10_800},
    %{key: "last_6h", label: "Last 6 hours", from: "now-6h", to: "now", seconds: 21_600},
    %{key: "last_12h", label: "Last 12 hours", from: "now-12h", to: "now", seconds: 43_200},
    %{key: "last_24h", label: "Last 24 hours", from: "now-24h", to: "now", seconds: 86_400}
  ]

  @type bound ::
          :now | {:relative, neg_integer()} | {:absolute, DateTime.t()}
  @type resolution ::
          {:sliding, pos_integer()} | {:absolute, DateTime.t(), DateTime.t()}

  @spec quick_ranges() :: [map()]
  def quick_ranges, do: @quick_ranges

  @spec quick_range(binary()) :: {:ok, map()} | :error
  def quick_range(key) when is_binary(key) do
    case Enum.find(@quick_ranges, &(&1.key == key)) do
      nil -> :error
      range -> {:ok, range}
    end
  end

  @spec max_sliding_window_seconds() :: pos_integer()
  def max_sliding_window_seconds, do: @max_sliding_window_seconds

  @spec parse_bound(term()) :: {:ok, bound()} | :error
  def parse_bound(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      "now" -> {:ok, :now}
      trimmed -> parse_offset_or_datetime(trimmed)
    end
  end

  def parse_bound(_value), do: :error

  @doc """
  Resolves a `from`/`to` bound pair against `now`.

  Returns `{:ok, {:sliding, window_seconds}}` when the pair describes a
  window ending at now, or `{:ok, {:absolute, from, to}}` with relative
  bounds frozen against `now`.
  """
  @spec resolve(term(), term(), DateTime.t()) ::
          {:ok, resolution()}
          | {:error, :invalid_time_bound | :time_range_reversed | :window_too_large}
  def resolve(from, to, %DateTime{} = now) do
    with {:ok, from_bound} <- parse_bound(from),
         {:ok, to_bound} <- parse_bound(to) do
      resolve_bounds(from_bound, to_bound, DateTime.truncate(now, :second))
    else
      :error -> {:error, :invalid_time_bound}
    end
  end

  @doc """
  Human label for a bound pair: "Last 6 hours" for sliding windows,
  "2026-08-01 10:00:00 to 2026-08-01 12:00:00 UTC" for absolute ranges.
  """
  @spec label(term(), term()) :: binary() | nil
  def label(from, to) do
    now = DateTime.utc_now()

    case resolve(from, to, now) do
      {:ok, {:sliding, window_seconds}} -> sliding_label(window_seconds)
      {:ok, {:absolute, from_value, to_value}} -> absolute_label(from_value, to_value)
      {:error, _reason} -> nil
    end
  end

  @doc """
  Freezes a bound pair into absolute ISO-8601 strings for surfaces that do
  not understand relative expressions (sliding windows resolve against
  `now`). Unresolvable pairs pass through unchanged.
  """
  @spec frozen_bounds(term(), term(), DateTime.t()) :: {term(), term()}
  def frozen_bounds(from, to, %DateTime{} = now) do
    case resolve(from, to, now) do
      {:ok, {:sliding, window_seconds}} ->
        to_value = DateTime.truncate(now, :second)
        from_value = DateTime.add(to_value, -window_seconds, :second)
        {DateTime.to_iso8601(from_value), DateTime.to_iso8601(to_value)}

      {:ok, {:absolute, from_value, to_value}} ->
        {DateTime.to_iso8601(from_value), DateTime.to_iso8601(to_value)}

      {:error, _reason} ->
        {from, to}
    end
  end

  @doc "Shifts an absolute range backwards or forwards by half its span."
  @spec shift({DateTime.t(), DateTime.t()}, :back | :forward) :: {DateTime.t(), DateTime.t()}
  def shift({%DateTime{} = from, %DateTime{} = to}, direction)
      when direction in [:back, :forward] do
    offset = max(div(span_seconds(from, to), 2), 1)
    offset = if direction == :back, do: -offset, else: offset
    {DateTime.add(from, offset, :second), DateTime.add(to, offset, :second)}
  end

  @doc "Doubles the span of an absolute range around its center."
  @spec zoom_out({DateTime.t(), DateTime.t()}) :: {DateTime.t(), DateTime.t()}
  def zoom_out({%DateTime{} = from, %DateTime{} = to}) do
    half = max(div(span_seconds(from, to), 2), 1)
    {DateTime.add(from, -half, :second), DateTime.add(to, half, :second)}
  end

  defp resolve_bounds({:relative, offset}, :now, _now)
       when -offset > @max_sliding_window_seconds,
       do: {:error, :window_too_large}

  defp resolve_bounds({:relative, offset}, :now, _now), do: {:ok, {:sliding, -offset}}

  defp resolve_bounds(from_bound, to_bound, now) do
    from_value = freeze(from_bound, now)
    to_value = freeze(to_bound, now)

    case DateTime.compare(from_value, to_value) do
      :lt -> {:ok, {:absolute, from_value, to_value}}
      _reversed_or_empty -> {:error, :time_range_reversed}
    end
  end

  defp freeze(:now, now), do: now
  defp freeze({:relative, offset}, now), do: DateTime.add(now, offset, :second)
  defp freeze({:absolute, datetime}, _now), do: DateTime.truncate(datetime, :second)

  defp parse_offset_or_datetime(value) do
    case Regex.run(@relative_pattern, value) do
      [_full, amount, unit] ->
        {:ok, {:relative, -String.to_integer(amount) * Map.fetch!(@unit_seconds, unit)}}

      nil ->
        parse_datetime(value)
    end
  end

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, {:absolute, datetime}}

      {:error, _reason} ->
        case DateTime.from_iso8601(value <> "Z") do
          {:ok, datetime, _offset} -> {:ok, {:absolute, datetime}}
          {:error, _reason} -> :error
        end
    end
  end

  defp span_seconds(from, to), do: DateTime.diff(to, from, :second)

  defp sliding_label(window_seconds) do
    case Enum.find(@quick_ranges, &(&1.seconds == window_seconds)) do
      %{label: label} -> label
      nil -> "Last " <> humanize_seconds(window_seconds)
    end
  end

  defp humanize_seconds(seconds) do
    {amount, unit} =
      [{604_800, "week"}, {86_400, "day"}, {3_600, "hour"}, {60, "minute"}, {1, "second"}]
      |> Enum.find_value(fn {unit_seconds, unit} ->
        if rem(seconds, unit_seconds) == 0 and seconds >= unit_seconds do
          {div(seconds, unit_seconds), unit}
        end
      end)

    "#{amount} #{unit}#{if amount == 1, do: "", else: "s"}"
  end

  defp absolute_label(from, to) do
    "#{format_timestamp(from)} to #{format_timestamp(to)} UTC"
  end

  defp format_timestamp(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end
end
