defmodule Cadence.Telemetry.DerivedItems.StatefulFunctionsTest do
  @moduledoc """
  Tests for stateful processor functions in the expression evaluator.

  Stateful functions maintain state across evaluations and are used for
  time-series analysis of telemetry data.
  """

  use ExUnit.Case

  alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator
  alias Cadence.Telemetry.DerivedItems.ExpressionParser
  alias Cadence.Telemetry.DerivedItems.ProcessorState

  # Not async because tests share ETS state
  @mission_id "test-mission-#{:erlang.unique_integer([:positive])}"

  setup do
    # Start ProcessorState if not running
    unless ProcessorState.available?() do
      start_supervised!(ProcessorState)
    end

    # Clear state for this test's mission
    ProcessorState.clear_mission(@mission_id)

    on_exit(fn ->
      ProcessorState.clear_mission(@mission_id)
    end)

    :ok
  end

  describe "rolling_avg/2" do
    test "computes rolling average over window" do
      bindings = %{"HEALTH.TEMP" => 10.0}

      # First sample - avg is the value itself
      {:ok, result1} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 3)",
          bindings,
          @mission_id,
          "TEMP_AVG"
        )

      assert_in_delta result1, 10.0, 0.001

      # Second sample
      {:ok, result2} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 20.0},
          @mission_id,
          "TEMP_AVG"
        )

      # (10 + 20) / 2 = 15
      assert_in_delta result2, 15.0, 0.001

      # Third sample
      {:ok, result3} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 30.0},
          @mission_id,
          "TEMP_AVG"
        )

      # (10 + 20 + 30) / 3 = 20
      assert_in_delta result3, 20.0, 0.001

      # Fourth sample - window slides
      {:ok, result4} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 40.0},
          @mission_id,
          "TEMP_AVG"
        )

      # (20 + 30 + 40) / 3 = 30
      assert_in_delta result4, 30.0, 0.001
    end

    test "different items have separate state" do
      bindings = %{"HEALTH.TEMP" => 100.0}

      {:ok, result1} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 5)",
          bindings,
          @mission_id,
          "ITEM_A"
        )

      {:ok, result2} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 5)",
          bindings,
          @mission_id,
          "ITEM_B"
        )

      # Both should be 100 since they have separate state
      assert_in_delta result1, 100.0, 0.001
      assert_in_delta result2, 100.0, 0.001
    end

    test "returns error for wrong arity" do
      assert {:error, {:invalid_arity, :rolling_avg, 2, 1}} =
               ExpressionEvaluator.evaluate_stateful(
                 "rolling_avg(HEALTH.TEMP)",
                 %{"HEALTH.TEMP" => 10.0},
                 @mission_id,
                 "TEST"
               )
    end
  end

  describe "rolling_min/2" do
    test "tracks minimum over window" do
      item_name = "TEMP_MIN_#{:erlang.unique_integer([:positive])}"

      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_min(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 50.0},
          @mission_id,
          item_name
        )

      assert_in_delta r1, 50.0, 0.001

      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_min(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 30.0},
          @mission_id,
          item_name
        )

      assert_in_delta r2, 30.0, 0.001

      {:ok, r3} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_min(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 40.0},
          @mission_id,
          item_name
        )

      # min(50, 30, 40) = 30
      assert_in_delta r3, 30.0, 0.001

      {:ok, r4} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_min(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 60.0},
          @mission_id,
          item_name
        )

      # Window slides: min(30, 40, 60) = 30
      assert_in_delta r4, 30.0, 0.001

      {:ok, r5} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_min(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 70.0},
          @mission_id,
          item_name
        )

      # Window slides: min(40, 60, 70) = 40
      assert_in_delta r5, 40.0, 0.001
    end
  end

  describe "rolling_max/2" do
    test "tracks maximum over window" do
      item_name = "TEMP_MAX_#{:erlang.unique_integer([:positive])}"

      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_max(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 10.0},
          @mission_id,
          item_name
        )

      assert_in_delta r1, 10.0, 0.001

      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_max(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 30.0},
          @mission_id,
          item_name
        )

      assert_in_delta r2, 30.0, 0.001

      {:ok, r3} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_max(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 20.0},
          @mission_id,
          item_name
        )

      # max(10, 30, 20) = 30
      assert_in_delta r3, 30.0, 0.001
    end
  end

  describe "stddev/2" do
    test "computes standard deviation over window" do
      item_name = "TEMP_STDDEV_#{:erlang.unique_integer([:positive])}"

      # First sample - stddev is 0 with one value
      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "stddev(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 10.0},
          @mission_id,
          item_name
        )

      assert_in_delta r1, 0.0, 0.001

      # Add more samples with known stddev
      {:ok, _} =
        ExpressionEvaluator.evaluate_stateful(
          "stddev(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 20.0},
          @mission_id,
          item_name
        )

      {:ok, r3} =
        ExpressionEvaluator.evaluate_stateful(
          "stddev(HEALTH.TEMP, 3)",
          %{"HEALTH.TEMP" => 30.0},
          @mission_id,
          item_name
        )

      # Values: [10, 20, 30], mean = 20
      # Variance = ((10-20)^2 + (20-20)^2 + (30-20)^2) / 3 = (100 + 0 + 100) / 3 = 66.67
      # StdDev = sqrt(66.67) ≈ 8.165
      assert_in_delta r3, 8.165, 0.01
    end
  end

  describe "rate/1" do
    test "computes rate of change per second" do
      item_name = "TEMP_RATE_#{:erlang.unique_integer([:positive])}"

      # First sample - no previous value, rate is 0
      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "rate(HEALTH.TEMP)",
          %{"HEALTH.TEMP" => 100.0},
          @mission_id,
          item_name
        )

      assert_in_delta r1, 0.0, 0.001

      # Wait a bit and add second sample
      Process.sleep(100)

      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "rate(HEALTH.TEMP)",
          %{"HEALTH.TEMP" => 110.0},
          @mission_id,
          item_name
        )

      # Rate should be approximately (110-100) / 0.1 = 100 per second
      # Allow for timing variance
      # At least 50 per second (if sleep was longer than expected)
      assert r2 > 50.0
      # Less than 200 per second (if sleep was shorter)
      assert r2 < 200.0
    end

    test "returns error for wrong arity" do
      assert {:error, {:invalid_arity, :rate, 1, 2}} =
               ExpressionEvaluator.evaluate_stateful(
                 "rate(HEALTH.TEMP, 10)",
                 %{"HEALTH.TEMP" => 10.0},
                 @mission_id,
                 "TEST"
               )
    end
  end

  describe "delta/1" do
    test "computes difference from previous value" do
      item_name = "TEMP_DELTA_#{:erlang.unique_integer([:positive])}"

      # First sample - no previous value, delta is 0
      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "delta(HEALTH.TEMP)",
          %{"HEALTH.TEMP" => 100.0},
          @mission_id,
          item_name
        )

      assert_in_delta r1, 0.0, 0.001

      # Second sample
      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "delta(HEALTH.TEMP)",
          %{"HEALTH.TEMP" => 115.0},
          @mission_id,
          item_name
        )

      assert_in_delta r2, 15.0, 0.001

      # Third sample - negative delta
      {:ok, r3} =
        ExpressionEvaluator.evaluate_stateful(
          "delta(HEALTH.TEMP)",
          %{"HEALTH.TEMP" => 110.0},
          @mission_id,
          item_name
        )

      assert_in_delta r3, -5.0, 0.001
    end
  end

  describe "count/0" do
    test "counts evaluations" do
      item_name = "COUNTER_#{:erlang.unique_integer([:positive])}"

      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "count()",
          %{},
          @mission_id,
          item_name
        )

      assert r1 == 1

      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "count()",
          %{},
          @mission_id,
          item_name
        )

      assert r2 == 2

      {:ok, r3} =
        ExpressionEvaluator.evaluate_stateful(
          "count()",
          %{},
          @mission_id,
          item_name
        )

      assert r3 == 3
    end

    test "different items have separate counts" do
      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "count()",
          %{},
          @mission_id,
          "COUNTER_A"
        )

      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "count()",
          %{},
          @mission_id,
          "COUNTER_B"
        )

      assert r1 == 1
      assert r2 == 1
    end
  end

  describe "elapsed/0" do
    test "tracks time since first evaluation" do
      item_name = "ELAPSED_#{:erlang.unique_integer([:positive])}"

      {:ok, r1} =
        ExpressionEvaluator.evaluate_stateful(
          "elapsed()",
          %{},
          @mission_id,
          item_name
        )

      # First call should be 0 or very close
      assert_in_delta r1, 0.0, 0.01

      # Wait and check again
      Process.sleep(100)

      {:ok, r2} =
        ExpressionEvaluator.evaluate_stateful(
          "elapsed()",
          %{},
          @mission_id,
          item_name
        )

      # Should be approximately 0.1 seconds
      assert r2 >= 0.08
      assert r2 <= 0.2
    end
  end

  describe "composite expressions with stateful functions" do
    test "stateful function in arithmetic expression" do
      item_name = "COMPOSITE_#{:erlang.unique_integer([:positive])}"
      bindings = %{"HEALTH.TEMP" => 20.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 3) * 2",
          bindings,
          @mission_id,
          item_name
        )

      assert_in_delta result, 40.0, 0.001
    end

    test "multiple stateful functions in expression" do
      item_name = "MULTI_STATEFUL_#{:erlang.unique_integer([:positive])}"
      bindings = %{"HEALTH.T1" => 10.0, "HEALTH.T2" => 20.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.T1, 5) + rolling_avg(HEALTH.T2, 5)",
          bindings,
          @mission_id,
          item_name
        )

      # Both averages are single values, so 10 + 20 = 30
      assert_in_delta result, 30.0, 0.001
    end

    test "stateful function in conditional" do
      item_name = "COND_STATEFUL_#{:erlang.unique_integer([:positive])}"

      # Build up some history
      for _ <- 1..5 do
        ExpressionEvaluator.evaluate_stateful(
          "rolling_avg(HEALTH.TEMP, 5)",
          %{"HEALTH.TEMP" => 50.0},
          @mission_id,
          item_name
        )
      end

      {:ok, result} =
        ExpressionEvaluator.evaluate_stateful(
          "if rolling_avg(HEALTH.TEMP, 5) > 40 then 1 else 0",
          %{"HEALTH.TEMP" => 50.0},
          @mission_id,
          item_name
        )

      assert result == 1
    end

    test "nested pure and stateful functions" do
      item_name = "NESTED_#{:erlang.unique_integer([:positive])}"
      bindings = %{"HEALTH.TEMP" => -15.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate_stateful(
          "abs(rolling_avg(HEALTH.TEMP, 3))",
          bindings,
          @mission_id,
          item_name
        )

      assert_in_delta result, 15.0, 0.001
    end
  end

  describe "ExpressionParser stateful function detection" do
    test "identifies stateful functions" do
      assert ExpressionParser.stateful_function?(:rolling_avg)
      assert ExpressionParser.stateful_function?(:rolling_min)
      assert ExpressionParser.stateful_function?(:rolling_max)
      assert ExpressionParser.stateful_function?(:stddev)
      assert ExpressionParser.stateful_function?(:rate)
      assert ExpressionParser.stateful_function?(:delta)
      assert ExpressionParser.stateful_function?(:count)
      assert ExpressionParser.stateful_function?(:elapsed)
    end

    test "identifies non-stateful functions" do
      refute ExpressionParser.stateful_function?(:abs)
      refute ExpressionParser.stateful_function?(:sqrt)
      refute ExpressionParser.stateful_function?(:min)
      refute ExpressionParser.stateful_function?(:max)
    end

    test "has_stateful_functions? detects stateful expressions" do
      assert {:ok, true} =
               ExpressionParser.has_stateful_functions?("rolling_avg(HEALTH.TEMP, 10)")

      assert {:ok, true} = ExpressionParser.has_stateful_functions?("rate(HEALTH.TEMP)")
      assert {:ok, true} = ExpressionParser.has_stateful_functions?("count()")
    end

    test "has_stateful_functions? returns false for pure expressions" do
      assert {:ok, false} = ExpressionParser.has_stateful_functions?("HEALTH.TEMP + 10")
      assert {:ok, false} = ExpressionParser.has_stateful_functions?("abs(HEALTH.TEMP)")
      assert {:ok, false} = ExpressionParser.has_stateful_functions?("max(HEALTH.T1, HEALTH.T2)")
    end

    test "has_stateful_functions? detects nested stateful functions" do
      assert {:ok, true} =
               ExpressionParser.has_stateful_functions?("abs(rolling_avg(HEALTH.TEMP, 10))")

      assert {:ok, true} =
               ExpressionParser.has_stateful_functions?("if rate(HEALTH.TEMP) > 0 then 1 else 0")
    end

    test "collect_stateful_calls returns all stateful function calls" do
      {:ok, calls} =
        ExpressionParser.collect_stateful_calls("rolling_avg(HEALTH.T1, 10) + rate(HEALTH.T2)")

      function_names = Enum.map(calls, fn {name, _args} -> name end)
      assert :rolling_avg in function_names
      assert :rate in function_names
    end
  end

  describe "ProcessorState" do
    test "get returns nil for non-existent state" do
      result = ProcessorState.get(@mission_id, {"unknown_item", {:unknown_fn, 123}})
      assert result == nil
    end

    test "put and get round-trip" do
      key = {"test_item", {:test_fn, 456}}
      state = %{buffer: [1, 2, 3], last_avg: 2.0}

      ProcessorState.put(@mission_id, key, state)
      result = ProcessorState.get(@mission_id, key)

      assert result == state
    end

    test "clear_mission removes all state for mission" do
      key1 = {"item1", {:fn1, 1}}
      key2 = {"item2", {:fn2, 2}}

      ProcessorState.put(@mission_id, key1, %{value: 1})
      ProcessorState.put(@mission_id, key2, %{value: 2})

      ProcessorState.clear_mission(@mission_id)

      assert ProcessorState.get(@mission_id, key1) == nil
      assert ProcessorState.get(@mission_id, key2) == nil
    end

    test "clear_item removes state for specific item" do
      key1 = {"item1", {:fn1, 1}}
      key2 = {"item2", {:fn2, 2}}

      ProcessorState.put(@mission_id, key1, %{value: 1})
      ProcessorState.put(@mission_id, key2, %{value: 2})

      ProcessorState.clear_item(@mission_id, "item1")

      assert ProcessorState.get(@mission_id, key1) == nil
      assert ProcessorState.get(@mission_id, key2) == %{value: 2}
    end

    test "stats returns table statistics" do
      stats = ProcessorState.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory_bytes)
    end
  end
end
