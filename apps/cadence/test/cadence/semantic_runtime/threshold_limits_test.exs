defmodule Cadence.SemanticRuntime.ThresholdLimitsTest do
  @moduledoc """
  Red/yellow thresholds evaluated by the monitoring evaluator give the answers the old threshold
  evaluator gave (#451 T2c): over thresholds with any subset of the four set (overlapping ones
  included) and values on, around and far from them. Random inputs from a printed seed.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.Limits.Evaluator
  alias Cadence.SemanticRuntime.ThresholdLimits

  @keys ["red_low", "yellow_low", "yellow_high", "red_high"]
  @states [:green, :blue, :yellow_low, :yellow_high, :red_low, :red_high]

  test "the same state as Limits.Evaluator for generated thresholds and values" do
    seed = :erlang.unique_integer([:positive])
    :rand.seed(:exsss, {seed, 11, 3})

    for n <- 1..3_000 do
      thresholds = thresholds()

      for value <- values(thresholds) do
        old = Evaluator.evaluate(value, thresholds)
        new = ThresholdLimits.limit_state(value, thresholds)

        assert new == old,
               "seed #{seed}, case #{n}: #{inspect(value)} against #{inspect(thresholds)}: " <>
                 "old #{old}, new #{new}"
      end
    end
  end

  test "the vocabulary functions agree for every state" do
    for state <- @states do
      assert ThresholdLimits.violation?(state) == Evaluator.violation?(state)
      assert ThresholdLimits.severity(state) == Evaluator.severity(state)
      assert ThresholdLimits.normalize_state(state) == Evaluator.normalize_state(state)
    end

    # A stored state this version does not know (#1025) is no violation of its own, rank 0.
    assert ThresholdLimits.severity(:unknown) == 0
    assert ThresholdLimits.normalize_state(:unknown) == :unknown
  end

  test "the fixed cases: precedence, boundaries (strict), a value that is not a number" do
    all = %{"red_low" => 0, "yellow_low" => 10, "yellow_high" => 50, "red_high" => 60}

    for {value, state} <- [
          {-1, :red_low},
          {0, :yellow_low},
          {5, :yellow_low},
          {10, :green},
          {30, :green},
          {50, :green},
          {55, :yellow_high},
          {60, :yellow_high},
          {61, :red_high}
        ] do
      assert ThresholdLimits.limit_state(value, all) == state, "#{value}"
    end

    # A red threshold beats a yellow one on the same side; with only yellow set, yellow.
    assert ThresholdLimits.limit_state(100, %{"yellow_high" => 50}) == :yellow_high
    assert ThresholdLimits.limit_state(100, %{"yellow_high" => 50, "red_high" => 80}) == :red_high
    assert ThresholdLimits.limit_state(5, %{}) == :green

    for value <- ["50", nil, true, :x, [1], %{}] do
      assert ThresholdLimits.limit_state(value, all) == :green
    end
  end

  test "thresholds compile to comparison rules the evaluator reads, red before yellow" do
    rules = ThresholdLimits.rules(%{"yellow_high" => 5, "red_low" => -1, "unknown_key" => 3})

    assert Enum.map(rules, &{&1.limit_state, &1.operator, &1.severity, &1.value}) == [
             {:red_low, :<, :critical, -1},
             {:yellow_high, :>, :warning, 5}
           ]
  end

  defp thresholds do
    present = Enum.filter(@keys, fn _ -> :rand.uniform() < 0.6 end)

    Map.new(present, fn key ->
      # Half near their usual place (sometimes equal or crossing), half anywhere: then several
      # thresholds match one value and the precedence (red low, red high, yellow low, yellow high)
      # decides.
      if :rand.uniform() < 0.5,
        do: {key, base(key) + :rand.uniform(7) - 4},
        else: {key, :rand.uniform(80) - 10}
    end)
  end

  defp base("red_low"), do: 0
  defp base("yellow_low"), do: 10
  defp base("yellow_high"), do: 50
  defp base("red_high"), do: 60

  defp values(thresholds) do
    around =
      thresholds
      |> Map.values()
      |> Enum.flat_map(&[&1 - 1, &1, &1 + 1, &1 + 0.5, &1 - 0.5])

    around ++ [-1_000, 1_000, 30, 30.5, :rand.uniform(80) - 10]
  end
end
