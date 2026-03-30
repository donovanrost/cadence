defmodule Cadence.Limits.Evaluator do
  @moduledoc """
  Evaluates numeric values against configured red/yellow limit thresholds.
  """

  @type limit_state :: :green | :yellow_low | :yellow_high | :red_low | :red_high | :blue
  @type limits_config :: %{optional(binary()) => number()}

  @spec evaluate(any(), limits_config()) :: limit_state()
  def evaluate(value, limits) when is_number(value) and is_map(limits) do
    cond do
      check_red_low(value, limits) -> :red_low
      check_red_high(value, limits) -> :red_high
      check_yellow_low(value, limits) -> :yellow_low
      check_yellow_high(value, limits) -> :yellow_high
      true -> :green
    end
  end

  def evaluate(_value, _limits), do: :green

  @spec violation?(limit_state()) :: boolean()
  def violation?(:green), do: false
  def violation?(:blue), do: false
  def violation?(_state), do: true

  @spec severity(limit_state()) :: non_neg_integer()
  def severity(:green), do: 0
  def severity(:blue), do: 0
  def severity(:yellow_low), do: 1
  def severity(:yellow_high), do: 1
  def severity(:red_low), do: 2
  def severity(:red_high), do: 2

  @spec normalize_state(limit_state()) :: :red | :yellow | :green | :blue
  def normalize_state(:red_low), do: :red
  def normalize_state(:red_high), do: :red
  def normalize_state(:yellow_low), do: :yellow
  def normalize_state(:yellow_high), do: :yellow
  def normalize_state(:green), do: :green
  def normalize_state(:blue), do: :blue

  defp check_red_low(value, limits) do
    case Map.get(limits, "red_low") do
      nil -> false
      threshold -> value < threshold
    end
  end

  defp check_red_high(value, limits) do
    case Map.get(limits, "red_high") do
      nil -> false
      threshold -> value > threshold
    end
  end

  defp check_yellow_low(value, limits) do
    case Map.get(limits, "yellow_low") do
      nil -> false
      threshold -> value < threshold
    end
  end

  defp check_yellow_high(value, limits) do
    case Map.get(limits, "yellow_high") do
      nil -> false
      threshold -> value > threshold
    end
  end
end
