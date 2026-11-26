defmodule Cadence.Observability.ScaleSampler.Stats do
  @moduledoc """
  Percentiles for individual sampler rows and run summaries (#717).
  """

  @counters ~w(ecto.count ingest.batches ingest.entries ingest.bytes ingest.frames ingest.packets
               ingest.samples storage.postgres_wal_bytes)

  @doc "p50, p99 and max of `values` (`nil`s when empty), rounded to 2 decimals."
  @spec distribution([number()]) :: %{
          p50: number() | nil,
          p99: number() | nil,
          max: number() | nil
        }
  def distribution([]), do: %{p50: nil, p99: nil, max: nil}

  def distribution(values) do
    sorted = Enum.sort(values)

    %{
      p50: round2(pick(sorted, 0.5)),
      p99: round2(pick(sorted, 0.99)),
      max: round2(List.last(sorted))
    }
  end

  @doc """
  Summarizes numeric metrics across rows. For counters, also reports the run total and the
  distribution of rates calculated with each row's own elapsed time.
  """
  @spec summarize([map()]) :: %{
          rows: non_neg_integer(),
          elapsed_ms: number(),
          metrics: %{binary() => map()},
          counters: %{binary() => %{total: number(), per_second: map()}}
        }
  def summarize(rows) do
    observations =
      rows
      |> Enum.flat_map(fn row ->
        Enum.map(leaves(row, []), fn {path, value} -> {path, {value, row[:elapsed_ms]}} end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    %{
      rows: length(rows),
      elapsed_ms: Enum.sum_by(rows, &(Map.get(&1, :elapsed_ms) || 0)),
      metrics:
        Map.new(observations, fn {path, values} ->
          {path, distribution(Enum.map(values, &elem(&1, 0)))}
        end),
      counters:
        observations
        |> Map.take(@counters)
        |> Map.new(fn {path, values} -> {path, counter_summary(values)} end)
    }
  end

  defp counter_summary(values) do
    rates =
      for {value, elapsed_ms} <- values,
          is_number(elapsed_ms) and elapsed_ms > 0,
          do: value * 1_000 / elapsed_ms

    %{total: Enum.sum_by(values, &elem(&1, 0)), per_second: distribution(rates)}
  end

  defp leaves(map, prefix) when is_map(map) do
    Enum.flat_map(map, fn {key, value} -> leaves(value, [to_string(key) | prefix]) end)
  end

  defp leaves(value, prefix) when is_number(value),
    do: [{prefix |> Enum.reverse() |> Enum.join("."), value}]

  defp leaves(_value, _prefix), do: []

  # Nearest-rank percentile on a sorted list.
  defp pick(sorted, q) do
    index = max(0, ceil(q * length(sorted)) - 1)
    Enum.at(sorted, index)
  end

  defp round2(value) when is_integer(value), do: value
  defp round2(value) when is_float(value), do: Float.round(value, 2)
end
