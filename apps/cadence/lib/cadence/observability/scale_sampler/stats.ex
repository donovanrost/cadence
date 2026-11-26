defmodule Cadence.Observability.ScaleSampler.Stats do
  @moduledoc """
  Pure aggregation for `Cadence.Observability.ScaleSampler` (#717): percentiles of one second's
  samples, and a run summary over the per-second rows.
  """

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
  A run summary: for every numeric leaf in the per-second rows (`path` => value), the p50, p99
  and max across seconds. Non-numeric leaves (timestamps, names) are skipped.
  """
  @spec summarize([map()]) :: %{seconds: non_neg_integer(), metrics: %{binary() => map()}}
  def summarize(rows) do
    metrics =
      rows
      |> Enum.flat_map(&leaves(&1, []))
      |> Enum.group_by(fn {path, _value} -> path end, fn {_path, value} -> value end)
      |> Map.new(fn {path, values} -> {path, distribution(values)} end)

    %{seconds: length(rows), metrics: metrics}
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
