defmodule Cadence.Telemetry.Limits.Evaluator do
  @moduledoc """
  Evaluates telemetry values against configured limits.

  Limits are defined as nested maps with named limit sets:

      %{
        "NOMINAL" => %{
          "red_low" => -50.0,
          "yellow_low" => -10.0,
          "yellow_high" => 85.0,
          "red_high" => 100.0
        }
      }

  The evaluation order is (from most to least severe):
  1. red_low / red_high - Critical limits
  2. yellow_low / yellow_high - Warning limits
  3. green - Within all limits

  Non-numeric values always evaluate to `:green`.

  ## Limit States

  - `:red_low` - Value below red low threshold
  - `:red_high` - Value above red high threshold
  - `:yellow_low` - Value below yellow low threshold (but above red_low)
  - `:yellow_high` - Value above yellow high threshold (but below red_high)
  - `:green` - Value within all limits
  - `:blue` - Stale data (not evaluated here, handled by StalenessMonitor)
  """

  @type limit_state :: :green | :yellow_low | :yellow_high | :red_low | :red_high | :blue
  @type limits_config :: %{optional(String.t()) => number()}

  @doc """
  Evaluates a value against a single limit set configuration.

  Returns the limit state based on the value's position relative to thresholds.

  ## Parameters

  - `value` - The telemetry value to evaluate
  - `limits` - Map containing limit thresholds (red_low, yellow_low, etc.)

  ## Examples

      iex> Evaluator.evaluate(95.0, %{"red_high" => 100.0, "yellow_high" => 85.0})
      :yellow_high

      iex> Evaluator.evaluate(50.0, %{"red_low" => 0.0, "red_high" => 100.0})
      :green

      iex> Evaluator.evaluate(-10.0, %{"red_low" => 0.0})
      :red_low

      iex> Evaluator.evaluate("string_value", %{"red_high" => 100.0})
      :green
  """
  @spec evaluate(any(), limits_config()) :: limit_state()
  def evaluate(value, limits) when is_number(value) and is_map(limits) do
    cond do
      # Red limits (most severe) - check first
      check_red_low(value, limits) -> :red_low
      check_red_high(value, limits) -> :red_high
      # Yellow limits (warning)
      check_yellow_low(value, limits) -> :yellow_low
      check_yellow_high(value, limits) -> :yellow_high
      # Within all limits
      true -> :green
    end
  end

  # Non-numeric values always evaluate to green
  def evaluate(_value, _limits), do: :green

  @doc """
  Evaluates a value using a named limit set from the limits configuration.

  ## Parameters

  - `value` - The telemetry value to evaluate
  - `limits_config` - Map of named limit sets (e.g., %{"NOMINAL" => %{...}, "ECLIPSE" => %{...}})
  - `active_set` - Name of the active limit set to use

  ## Examples

      iex> config = %{
      ...>   "NOMINAL" => %{"red_high" => 100.0, "yellow_high" => 85.0},
      ...>   "ECLIPSE" => %{"red_high" => 80.0, "yellow_high" => 60.0}
      ...> }
      iex> Evaluator.evaluate_with_set(75.0, config, "NOMINAL")
      :green
      iex> Evaluator.evaluate_with_set(75.0, config, "ECLIPSE")
      :yellow_high
  """
  @spec evaluate_with_set(any(), map(), String.t()) :: limit_state()
  def evaluate_with_set(value, limits_config, active_set) when is_map(limits_config) do
    case Map.get(limits_config, active_set) do
      nil -> :green
      limits -> evaluate(value, limits)
    end
  end

  @doc """
  Checks if a limit state represents a violation (non-green).

  ## Examples

      iex> Evaluator.violation?(:red_high)
      true

      iex> Evaluator.violation?(:green)
      false

      iex> Evaluator.violation?(:blue)
      false
  """
  @spec violation?(limit_state()) :: boolean()
  def violation?(:green), do: false
  def violation?(:blue), do: false
  def violation?(_state), do: true

  @doc """
  Returns the severity level of a limit state (higher = more severe).

  Used for comparing states and determining if a state change is an
  escalation or de-escalation.

  ## Examples

      iex> Evaluator.severity(:green)
      0

      iex> Evaluator.severity(:yellow_high)
      1

      iex> Evaluator.severity(:red_low)
      2
  """
  @spec severity(limit_state()) :: non_neg_integer()
  def severity(:green), do: 0
  def severity(:blue), do: 0
  def severity(:yellow_low), do: 1
  def severity(:yellow_high), do: 1
  def severity(:red_low), do: 2
  def severity(:red_high), do: 2

  @doc """
  Normalizes a limit state to its base color for CVT storage.

  The CVT stores simplified states (:red, :yellow, :green, :blue) rather than
  directional states (:red_low, :red_high, etc.).

  ## Examples

      iex> Evaluator.normalize_state(:red_low)
      :red

      iex> Evaluator.normalize_state(:yellow_high)
      :yellow

      iex> Evaluator.normalize_state(:green)
      :green
  """
  @spec normalize_state(limit_state()) :: :red | :yellow | :green | :blue
  def normalize_state(:red_low), do: :red
  def normalize_state(:red_high), do: :red
  def normalize_state(:yellow_low), do: :yellow
  def normalize_state(:yellow_high), do: :yellow
  def normalize_state(:green), do: :green
  def normalize_state(:blue), do: :blue

  # Private helper functions

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
