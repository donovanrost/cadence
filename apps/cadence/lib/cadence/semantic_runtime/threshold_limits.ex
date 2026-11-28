defmodule Cadence.SemanticRuntime.ThresholdLimits do
  @moduledoc """
  Red/yellow limit thresholds evaluated by the monitoring evaluator (#451 T2c).

  A ground limit definition is four optional thresholds (`red_low`, `yellow_low`, `yellow_high`,
  `red_high`). They are monitoring rules like any other: a threshold below or above a value is a
  `:comparison` rule with a plan severity (red `critical`, yellow `warning`), and
  `MonitoringEvaluator` picks the matching rule of the highest severity, the first of equals in the
  order red low, red high, yellow low, yellow high. This module compiles the thresholds to those
  rules, evaluates through the evaluator, and names the result in the ground-limit vocabulary the
  stored states keep (`green`, `blue`, `yellow_low`, `yellow_high`, `red_low`, `red_high`; the
  normalized `red | yellow | green | blue`).

  It replaced the old red/yellow evaluator (deleted with this module's arrival) for
  `Limits.evaluate_source_samples/3` (the batch ground
  evaluation) and the dashboards' recomputed analysis, so one evaluator serves them and the live
  partitions. The answers are identical to the old evaluator's (a test compares them over generated
  thresholds and values); when the revision's compiled monitoring plan carries the limits (#451 T3)
  the rules come from it and this compile step goes away.
  """

  alias Cadence.SemanticRuntime.MonitoringEvaluator

  @type limit_state :: :green | :blue | :yellow_low | :yellow_high | :red_low | :red_high
  @type normalized_state :: :red | :yellow | :green | :blue

  # {threshold key, operator, plan severity, the state a match names}, in precedence order.
  @thresholds [
    {"red_low", :<, :critical, :red_low},
    {"red_high", :>, :critical, :red_high},
    {"yellow_low", :<, :warning, :yellow_low},
    {"yellow_high", :>, :warning, :yellow_high}
  ]

  @doc "The monitoring rules a thresholds map compiles to (each tagged with the state it names)."
  @spec rules(map()) :: [map()]
  def rules(thresholds) when is_map(thresholds) do
    for {key, operator, severity, state} <- @thresholds,
        threshold = Map.get(thresholds, key),
        not is_nil(threshold) do
      %{
        kind: :comparison,
        operator: operator,
        value: threshold,
        severity: severity,
        limit_state: state
      }
    end
  end

  @doc "The ground-limit state of a value against thresholds; a non-number is `:green`."
  @spec limit_state(term(), map()) :: limit_state()
  def limit_state(value, thresholds) when is_number(value) and is_map(thresholds) do
    case thresholds |> rules() |> MonitoringEvaluator.best_rule(value) do
      nil -> :green
      %{limit_state: state} -> state
    end
  end

  def limit_state(_value, _thresholds), do: :green

  @spec violation?(limit_state() | :unknown) :: boolean()
  def violation?(:green), do: false
  def violation?(:blue), do: false
  def violation?(_state), do: true

  @spec severity(limit_state() | :unknown) :: non_neg_integer()
  def severity(state) when state in [:green, :blue, :unknown], do: 0
  def severity(state) when state in [:yellow_low, :yellow_high], do: 1
  def severity(state) when state in [:red_low, :red_high], do: 2

  @spec normalize_state(limit_state() | :unknown) :: normalized_state() | :unknown
  def normalize_state(state) when state in [:red_low, :red_high], do: :red
  def normalize_state(state) when state in [:yellow_low, :yellow_high], do: :yellow
  def normalize_state(state) when state in [:green, :blue, :unknown], do: state
end
