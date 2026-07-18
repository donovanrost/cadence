defmodule Cadence.ContactPlanning.RequirementSchedule do
  @moduledoc "Normalized UTC schedules and bounded occurrence calculation for Requirement Templates."

  alias Cadence.Persistence.JsonDocument

  @maximum_interval_seconds 31 * 24 * 60 * 60
  @maximum_window_seconds 7 * 24 * 60 * 60

  @spec normalize(map()) :: map()
  def normalize(document) when is_map(document) do
    document
    |> JsonDocument.encode()
    |> normalize_type()
    |> validate_active_range()
  end

  def normalize(_document), do: raise(ArgumentError, "schedule_document must be an object")

  @spec occurrences_between(map(), DateTime.t(), DateTime.t(), pos_integer()) :: [DateTime.t()]
  def occurrences_between(schedule, %DateTime{} = from, %DateTime{} = until, limit)
      when is_map(schedule) and is_integer(limit) and limit > 0 do
    from = DateTime.truncate(from, :microsecond)
    until = DateTime.truncate(until, :microsecond)

    if DateTime.after?(from, until) do
      []
    else
      schedule
      |> normalize()
      |> occurrences(from, until)
      |> Enum.take(limit)
    end
  end

  @spec window(map(), DateTime.t()) :: {DateTime.t(), DateTime.t()}
  def window(schedule, %DateTime{} = occurrence_at) do
    schedule = normalize(schedule)
    earliest_start = DateTime.add(occurrence_at, schedule["window_offset_seconds"], :second)
    latest_end = DateTime.add(earliest_start, schedule["window_duration_seconds"], :second)
    {earliest_start, latest_end}
  end

  defp normalize_type(%{"type" => "fixed_interval"} = schedule) do
    %{
      "type" => "fixed_interval",
      "anchor_at" => timestamp!(schedule["anchor_at"], "anchor_at"),
      "ends_at" => optional_timestamp!(schedule["ends_at"], "ends_at"),
      "interval_seconds" =>
        bounded_positive!(
          schedule["interval_seconds"],
          60,
          @maximum_interval_seconds,
          "interval_seconds"
        ),
      "window_offset_seconds" =>
        bounded_integer!(
          Map.get(schedule, "window_offset_seconds", 0),
          -@maximum_window_seconds,
          @maximum_window_seconds,
          "window_offset_seconds"
        ),
      "window_duration_seconds" =>
        bounded_positive!(
          schedule["window_duration_seconds"],
          60,
          @maximum_window_seconds,
          "window_duration_seconds"
        )
    }
  end

  defp normalize_type(%{"type" => "daily"} = schedule) do
    %{
      "type" => "daily",
      "anchor_at" => timestamp!(schedule["anchor_at"], "anchor_at"),
      "ends_at" => optional_timestamp!(schedule["ends_at"], "ends_at"),
      "time_utc" => time!(schedule["time_utc"]),
      "window_offset_seconds" =>
        bounded_integer!(
          Map.get(schedule, "window_offset_seconds", 0),
          -@maximum_window_seconds,
          @maximum_window_seconds,
          "window_offset_seconds"
        ),
      "window_duration_seconds" =>
        bounded_positive!(
          schedule["window_duration_seconds"],
          60,
          @maximum_window_seconds,
          "window_duration_seconds"
        )
    }
  end

  defp normalize_type(%{"type" => type}),
    do: raise(ArgumentError, "unsupported Requirement schedule type: #{inspect(type)}")

  defp normalize_type(_schedule), do: raise(ArgumentError, "schedule type is required")

  defp validate_active_range(%{"ends_at" => nil} = schedule), do: schedule

  defp validate_active_range(schedule) do
    anchor = parse_timestamp!(schedule["anchor_at"], "anchor_at")
    ends_at = parse_timestamp!(schedule["ends_at"], "ends_at")

    if DateTime.after?(ends_at, anchor),
      do: schedule,
      else: raise(ArgumentError, "schedule ends_at must be after anchor_at")
  end

  defp occurrences(%{"type" => "fixed_interval"} = schedule, from, until) do
    anchor = parse_timestamp!(schedule["anchor_at"], "anchor_at")
    active_until = active_until(schedule, until)
    first = first_interval_occurrence(anchor, from, schedule["interval_seconds"])

    first
    |> Stream.iterate(&DateTime.add(&1, schedule["interval_seconds"], :second))
    |> Stream.take_while(&(not DateTime.after?(&1, active_until)))
  end

  defp occurrences(%{"type" => "daily"} = schedule, from, until) do
    anchor = parse_timestamp!(schedule["anchor_at"], "anchor_at")
    active_from = later(from, anchor)
    active_until = active_until(schedule, until)
    time = parse_time!(schedule["time_utc"])

    if DateTime.after?(active_from, active_until) do
      []
    else
      active_from
      |> DateTime.to_date()
      |> Date.range(DateTime.to_date(active_until))
      |> Enum.map(&DateTime.new!(&1, time, "Etc/UTC"))
      |> Enum.map(&normalize_precision/1)
      |> Enum.filter(fn occurrence ->
        not DateTime.before?(occurrence, active_from) and
          not DateTime.after?(occurrence, active_until)
      end)
    end
  end

  defp first_interval_occurrence(anchor, from, interval_seconds) do
    if DateTime.before?(from, anchor) do
      anchor
    else
      seconds = DateTime.diff(from, anchor, :second)
      steps = div(seconds + interval_seconds - 1, interval_seconds)
      DateTime.add(anchor, steps * interval_seconds, :second)
    end
  end

  defp active_until(%{"ends_at" => nil}, until), do: until

  defp active_until(%{"ends_at" => ends_at}, until) do
    earlier(until, parse_timestamp!(ends_at, "ends_at"))
  end

  defp timestamp!(value, field), do: value |> parse_timestamp!(field) |> DateTime.to_iso8601()
  defp optional_timestamp!(nil, _field), do: nil
  defp optional_timestamp!(value, field), do: timestamp!(value, field)

  defp parse_timestamp!(%DateTime{} = value, _field), do: normalize_precision(value)

  defp parse_timestamp!(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> normalize_precision(parsed)
      _other -> raise ArgumentError, "#{field} must be an ISO 8601 timestamp"
    end
  end

  defp parse_timestamp!(_value, field),
    do: raise(ArgumentError, "#{field} must be an ISO 8601 timestamp")

  defp time!(value), do: value |> parse_time!() |> Time.to_iso8601()

  defp parse_time!(%Time{} = value), do: Time.truncate(value, :second)

  defp parse_time!(value) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, parsed} -> Time.truncate(parsed, :second)
      _other -> raise ArgumentError, "time_utc must be an ISO 8601 time"
    end
  end

  defp parse_time!(_value), do: raise(ArgumentError, "time_utc must be an ISO 8601 time")

  defp bounded_positive!(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: value

  defp bounded_positive!(_value, minimum, maximum, field),
    do: raise(ArgumentError, "#{field} must be between #{minimum} and #{maximum}")

  defp bounded_integer!(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: value

  defp bounded_integer!(_value, minimum, maximum, field),
    do: raise(ArgumentError, "#{field} must be between #{minimum} and #{maximum}")

  defp normalize_precision(%DateTime{} = value) do
    {microseconds, _precision} = value.microsecond
    %{value | microsecond: {microseconds, 6}}
  end

  defp earlier(left, right), do: if(DateTime.before?(left, right), do: left, else: right)
  defp later(left, right), do: if(DateTime.after?(left, right), do: left, else: right)
end
