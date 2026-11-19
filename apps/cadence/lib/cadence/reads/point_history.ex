defmodule Cadence.Reads.PointHistory do
  @moduledoc """
  Decimated history of one telemetry point over a generation-time window, as
  fixed-width min/max/mean buckets.

  Uses the history store's native decimation when the backend supports it
  (QuestDB `SAMPLE BY`); otherwise reads raw samples (bounded) and buckets them
  here, so every backend returns the same shape. Only numeric values are
  bucketed. Callers authorize first.
  """

  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.Sample

  @raw_sample_limit 20_000

  @type bucket :: %{
          t: DateTime.t(),
          t_end: DateTime.t(),
          min: number(),
          max: number(),
          mean: number(),
          count: pos_integer()
        }

  @spec load(binary(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def load(
        organization_id,
        mission_id,
        point_id,
        %{from: from, to: to, max_points: max_points} = q
      ) do
    width_ms = bucket_width_ms(from, to, max_points)

    opts = [
      spacecraft_id: q[:spacecraft_id],
      from_observed_at: from,
      to_observed_at: to,
      bucket_width_ms: width_ms
    ]

    case TelemetryReads.decimated_sample_history_result(
           organization_id,
           mission_id,
           point_id,
           opts
         ) do
      {:ok, %{buckets: buckets}} ->
        {:ok, result(width_ms, Enum.flat_map(buckets, &native_bucket/1), false)}

      {:error, {:unsupported_history_capability, _backend, _capability}} ->
        fallback(organization_id, mission_id, point_id, opts, from, width_ms)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Bucket width (ms) that yields at most `max_points` buckets over the window."
  @spec bucket_width_ms(DateTime.t(), DateTime.t(), pos_integer()) :: pos_integer()
  def bucket_width_ms(from, to, max_points) do
    span_ms = max(DateTime.diff(to, from, :millisecond), 1)
    max(div(span_ms + max_points - 1, max_points), 1)
  end

  @doc """
  Buckets samples by generation time (receipt time when absent), numeric values
  only. Buckets sit on the same grid as QuestDB's `ALIGN TO CALENDAR`: multiples
  of the width from UTC midnight of the window's first day.
  """
  @spec bucket_samples([Sample.t()], DateTime.t(), pos_integer()) :: [bucket()]
  def bucket_samples(samples, from, width_ms) do
    origin =
      from
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.to_unix(:millisecond)

    samples
    |> Enum.flat_map(fn %Sample{} = sample ->
      at = sample.generation_time || sample.receipt_time
      value = numeric(sample.engineering_value)

      if at && value,
        do: [{div(DateTime.to_unix(at, :millisecond) - origin, width_ms), value}],
        else: []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {index, values} ->
      start = DateTime.from_unix!(origin + index * width_ms, :millisecond)

      %{
        t: start,
        t_end: DateTime.add(start, width_ms, :millisecond),
        min: Enum.min(values),
        max: Enum.max(values),
        mean: Enum.sum(values) / length(values),
        count: length(values)
      }
    end)
  end

  defp fallback(organization_id, mission_id, point_id, opts, from, width_ms) do
    samples =
      TelemetryReads.sample_history(
        organization_id,
        mission_id,
        point_id,
        Keyword.merge(opts, limit: @raw_sample_limit + 1, order: :asc)
      )

    truncated? = length(samples) > @raw_sample_limit
    samples = Enum.take(samples, @raw_sample_limit)

    {:ok, result(width_ms, bucket_samples(samples, from, width_ms), truncated?)}
  end

  defp native_bucket(%{bucket_start: %DateTime{} = start, sample_count: count} = bucket)
       when is_integer(count) and count > 0 do
    [
      %{
        t: start,
        t_end: bucket.bucket_end,
        min: bucket.min,
        max: bucket.max,
        mean: bucket.mean,
        count: count
      }
    ]
  end

  defp native_bucket(_empty), do: []

  defp result(width_ms, buckets, truncated?),
    do: %{bucket_width_ms: width_ms, buckets: buckets, truncated: truncated?}

  defp numeric(value) when is_number(value), do: value
  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(true), do: 1
  defp numeric(false), do: 0
  defp numeric(_other), do: nil
end
