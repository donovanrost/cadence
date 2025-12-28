defmodule Cadence.Procedures.PrimitivesTest do
  use Cadence.DataCase, async: true

  alias Cadence.Procedures.Primitives

  describe "resolve_value/2" do
    test "returns non-string values as-is" do
      context = %{mission_id: "m1", target_id: "t1"}

      assert Primitives.resolve_value(123, context) == 123
      assert Primitives.resolve_value(12.5, context) == 12.5
      assert Primitives.resolve_value(true, context) == true
      assert Primitives.resolve_value(nil, context) == nil
      assert Primitives.resolve_value(%{a: 1}, context) == %{a: 1}
    end

    test "returns plain strings as-is" do
      context = %{mission_id: "m1", target_id: "t1"}

      assert Primitives.resolve_value("hello", context) == "hello"
      assert Primitives.resolve_value("some value", context) == "some value"
    end

    test "resolves params references" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{"target_temp" => 45, "mode" => "safe"}
      }

      assert Primitives.resolve_value("params.target_temp", context) == 45
      assert Primitives.resolve_value("params.mode", context) == "safe"
      assert Primitives.resolve_value("params.missing", context) == nil
    end

    test "resolves params with atom keys" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{target_temp: 45}
      }

      assert Primitives.resolve_value("params.target_temp", context) == 45
    end

    test "resolves vars references" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        vars: %{"check_power.result" => true, "step1.value" => 42}
      }

      assert Primitives.resolve_value("vars.check_power.result", context) == true
      assert Primitives.resolve_value("vars.step1.value", context) == 42
    end

    test "resolves trigger references" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        trigger: %{"event" => "alarm", "source" => %{"id" => "src1"}}
      }

      assert Primitives.resolve_value("trigger.event", context) == "alarm"
      assert Primitives.resolve_value("trigger.source.id", context) == "src1"
    end

    test "resolves template strings" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{"name" => "Heater", "zone" => 1}
      }

      result =
        Primitives.resolve_value("Enabling {{params.name}} in zone {{params.zone}}", context)

      assert result == "Enabling Heater in zone 1"
    end
  end

  describe "resolve_values/2" do
    test "resolves all values in a map" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{"x" => 10, "y" => 20}
      }

      input = %{a: "params.x", b: "params.y", c: 123}
      result = Primitives.resolve_values(input, context)

      assert result == %{a: 10, b: 20, c: 123}
    end

    test "resolves all values in a list" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{"x" => 10}
      }

      input = ["params.x", "literal", 42]
      result = Primitives.resolve_values(input, context)

      assert result == [10, "literal", 42]
    end
  end

  describe "resolve_duration/2" do
    test "returns integers as-is" do
      context = %{mission_id: "m1", target_id: "t1"}
      assert Primitives.resolve_duration(5000, context) == 5000
    end

    test "resolves string references to integers" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{"delay" => 1000}
      }

      assert Primitives.resolve_duration("params.delay", context) == 1000
    end

    test "parses string numbers" do
      context = %{mission_id: "m1", target_id: "t1"}
      assert Primitives.resolve_duration("5000", context) == 5000
    end

    test "returns 0 for invalid values" do
      context = %{mission_id: "m1", target_id: "t1"}
      assert Primitives.resolve_duration("invalid", context) == 0
      assert Primitives.resolve_duration(nil, context) == 0
    end
  end

  describe "compare_values/3" do
    test "compares equality" do
      assert Primitives.compare_values(42, "==", 42) == true
      assert Primitives.compare_values(42, "==", 43) == false
      assert Primitives.compare_values("safe", "==", "safe") == true
      assert Primitives.compare_values("safe", "==", "unsafe") == false
    end

    test "compares inequality" do
      assert Primitives.compare_values(42, "!=", 43) == true
      assert Primitives.compare_values(42, "!=", 42) == false
    end

    test "compares numeric greater than or equal" do
      assert Primitives.compare_values(28.5, ">=", 24) == true
      assert Primitives.compare_values(24, ">=", 24) == true
      assert Primitives.compare_values(20, ">=", 24) == false
    end

    test "compares numeric less than or equal" do
      assert Primitives.compare_values(20, "<=", 24) == true
      assert Primitives.compare_values(24, "<=", 24) == true
      assert Primitives.compare_values(28, "<=", 24) == false
    end

    test "compares numeric greater than" do
      assert Primitives.compare_values(25, ">", 24) == true
      assert Primitives.compare_values(24, ">", 24) == false
    end

    test "compares numeric less than" do
      assert Primitives.compare_values(23, "<", 24) == true
      assert Primitives.compare_values(24, "<", 24) == false
    end

    test "returns false for non-numeric comparisons with numeric operators" do
      assert Primitives.compare_values("abc", ">=", 24) == false
      assert Primitives.compare_values(24, ">=", "abc") == false
    end
  end

  describe "wait/2" do
    test "waits for the specified duration" do
      start = System.monotonic_time(:millisecond)
      Primitives.wait(100)
      elapsed = System.monotonic_time(:millisecond) - start

      # Allow some tolerance
      assert elapsed >= 90
      assert elapsed < 200
    end

    test "calls progress callback for longer waits" do
      test_pid = self()

      callback = fn name, progress ->
        send(test_pid, {:progress, name, progress})
        :ok
      end

      # Use longer duration to ensure we get progress callbacks
      Primitives.wait(1500, on_progress: callback, name: "test_wait", update_interval: 300)

      # Should have received at least one progress update
      assert_received {:progress, "test_wait", %{type: :wait, total_ms: 1500}}
    end
  end

  describe "check_condition/2" do
    test "evaluates literal true" do
      context = %{mission_id: "m1", target_id: "t1"}
      assert Primitives.check_condition("true", context) == {:ok, true}
    end

    test "evaluates literal false" do
      context = %{mission_id: "m1", target_id: "t1"}
      assert Primitives.check_condition("false", context) == {:ok, false}
    end

    test "evaluates parameter comparisons" do
      context = %{
        mission_id: "m1",
        target_id: "t1",
        params: %{"threshold" => 50}
      }

      assert Primitives.check_condition("params.threshold > 40", context) == {:ok, true}
      assert Primitives.check_condition("params.threshold > 60", context) == {:ok, false}
    end
  end
end
