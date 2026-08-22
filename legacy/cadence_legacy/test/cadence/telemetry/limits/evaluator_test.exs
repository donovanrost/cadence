defmodule Cadence.Telemetry.Limits.EvaluatorTest do
  @moduledoc """
  Unit tests for the limits evaluator.

  Tests limit state evaluation for telemetry values against
  configured thresholds.
  """

  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Limits.Evaluator

  describe "evaluate/2 with numeric values" do
    test "returns :green when value is within all limits" do
      limits = %{
        "red_low" => 0.0,
        "yellow_low" => 10.0,
        "yellow_high" => 90.0,
        "red_high" => 100.0
      }

      assert Evaluator.evaluate(50.0, limits) == :green
    end

    test "returns :red_low when value is below red_low threshold" do
      limits = %{"red_low" => 0.0, "yellow_low" => 10.0}
      assert Evaluator.evaluate(-5.0, limits) == :red_low
    end

    test "returns :red_high when value is above red_high threshold" do
      limits = %{"red_high" => 100.0, "yellow_high" => 90.0}
      assert Evaluator.evaluate(105.0, limits) == :red_high
    end

    test "returns :yellow_low when value is below yellow_low but above red_low" do
      limits = %{
        "red_low" => 0.0,
        "yellow_low" => 10.0
      }

      assert Evaluator.evaluate(5.0, limits) == :yellow_low
    end

    test "returns :yellow_high when value is above yellow_high but below red_high" do
      limits = %{
        "yellow_high" => 90.0,
        "red_high" => 100.0
      }

      assert Evaluator.evaluate(95.0, limits) == :yellow_high
    end

    test "handles partial limits configuration (only red_high)" do
      limits = %{"red_high" => 100.0}

      assert Evaluator.evaluate(50.0, limits) == :green
      assert Evaluator.evaluate(150.0, limits) == :red_high
    end

    test "handles partial limits configuration (only yellow_low)" do
      limits = %{"yellow_low" => 10.0}

      assert Evaluator.evaluate(50.0, limits) == :green
      assert Evaluator.evaluate(5.0, limits) == :yellow_low
    end

    test "returns :green when no limits are configured" do
      assert Evaluator.evaluate(50.0, %{}) == :green
    end

    test "red limits take priority over yellow limits" do
      # Value that triggers both red_low and yellow_low
      limits = %{
        "red_low" => 0.0,
        "yellow_low" => 10.0
      }

      # -5 is below both thresholds, but red should win
      assert Evaluator.evaluate(-5.0, limits) == :red_low
    end

    test "handles integer values" do
      limits = %{"red_low" => 0, "red_high" => 100}

      assert Evaluator.evaluate(50, limits) == :green
      assert Evaluator.evaluate(-5, limits) == :red_low
      assert Evaluator.evaluate(105, limits) == :red_high
    end

    test "handles edge cases at exact threshold values" do
      limits = %{
        "red_low" => 0.0,
        "yellow_low" => 10.0,
        "yellow_high" => 90.0,
        "red_high" => 100.0
      }

      # At threshold values, we use < and > (not <= and >=)
      # Exactly at red_low (0.0) - not below it, so not red_low
      # But 0.0 < yellow_low (10.0), so it's yellow_low
      assert Evaluator.evaluate(0.0, limits) == :yellow_low

      # Exactly at red_high (100.0) - not above it, so not red_high
      # But 100.0 > yellow_high (90.0), so it's yellow_high
      assert Evaluator.evaluate(100.0, limits) == :yellow_high

      # Value within all limits
      assert Evaluator.evaluate(50.0, limits) == :green

      # Just below red_low should trigger red_low
      assert Evaluator.evaluate(-0.001, limits) == :red_low

      # Just above red_high should trigger red_high
      assert Evaluator.evaluate(100.001, limits) == :red_high
    end
  end

  describe "evaluate/2 with non-numeric values" do
    test "returns :green for string values" do
      limits = %{"red_high" => 100.0}
      assert Evaluator.evaluate("some_string", limits) == :green
    end

    test "returns :green for nil values" do
      limits = %{"red_high" => 100.0}
      assert Evaluator.evaluate(nil, limits) == :green
    end

    test "returns :green for boolean values" do
      limits = %{"red_high" => 100.0}
      assert Evaluator.evaluate(true, limits) == :green
      assert Evaluator.evaluate(false, limits) == :green
    end

    test "returns :green for map values" do
      limits = %{"red_high" => 100.0}
      assert Evaluator.evaluate(%{}, limits) == :green
    end
  end

  describe "evaluate_with_set/3" do
    test "evaluates using the specified limit set" do
      config = %{
        "NOMINAL" => %{"red_high" => 100.0, "yellow_high" => 85.0},
        "ECLIPSE" => %{"red_high" => 80.0, "yellow_high" => 60.0}
      }

      # 75 is green in NOMINAL but yellow_high in ECLIPSE
      assert Evaluator.evaluate_with_set(75.0, config, "NOMINAL") == :green
      assert Evaluator.evaluate_with_set(75.0, config, "ECLIPSE") == :yellow_high
    end

    test "returns :green when limit set does not exist" do
      config = %{
        "NOMINAL" => %{"red_high" => 100.0}
      }

      assert Evaluator.evaluate_with_set(150.0, config, "NONEXISTENT") == :green
    end

    test "handles empty config" do
      assert Evaluator.evaluate_with_set(50.0, %{}, "NOMINAL") == :green
    end
  end

  describe "violation?/1" do
    test "returns false for :green" do
      assert Evaluator.violation?(:green) == false
    end

    test "returns false for :blue" do
      assert Evaluator.violation?(:blue) == false
    end

    test "returns true for :yellow_low" do
      assert Evaluator.violation?(:yellow_low) == true
    end

    test "returns true for :yellow_high" do
      assert Evaluator.violation?(:yellow_high) == true
    end

    test "returns true for :red_low" do
      assert Evaluator.violation?(:red_low) == true
    end

    test "returns true for :red_high" do
      assert Evaluator.violation?(:red_high) == true
    end
  end

  describe "severity/1" do
    test "green has severity 0" do
      assert Evaluator.severity(:green) == 0
    end

    test "blue has severity 0" do
      assert Evaluator.severity(:blue) == 0
    end

    test "yellow states have severity 1" do
      assert Evaluator.severity(:yellow_low) == 1
      assert Evaluator.severity(:yellow_high) == 1
    end

    test "red states have severity 2" do
      assert Evaluator.severity(:red_low) == 2
      assert Evaluator.severity(:red_high) == 2
    end
  end

  describe "normalize_state/1" do
    test "normalizes :red_low to :red" do
      assert Evaluator.normalize_state(:red_low) == :red
    end

    test "normalizes :red_high to :red" do
      assert Evaluator.normalize_state(:red_high) == :red
    end

    test "normalizes :yellow_low to :yellow" do
      assert Evaluator.normalize_state(:yellow_low) == :yellow
    end

    test "normalizes :yellow_high to :yellow" do
      assert Evaluator.normalize_state(:yellow_high) == :yellow
    end

    test "keeps :green as :green" do
      assert Evaluator.normalize_state(:green) == :green
    end

    test "keeps :blue as :blue" do
      assert Evaluator.normalize_state(:blue) == :blue
    end
  end
end
