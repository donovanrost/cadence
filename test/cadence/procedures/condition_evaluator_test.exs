defmodule Cadence.Procedures.ConditionEvaluatorTest do
  @moduledoc """
  Tests for the ConditionEvaluator module.

  This is SAFETY-CRITICAL code - the evaluator determines whether
  procedures abort, continue, or skip steps. Coverage must be comprehensive.
  """
  use ExUnit.Case, async: true

  alias Cadence.Procedures.ConditionEvaluator

  import Cadence.ProceduresBuilders

  # ============================================================================
  # Boolean Literals
  # ============================================================================

  describe "evaluate/2 with boolean literals" do
    test "string 'true' evaluates to true" do
      assert {:ok, true} = ConditionEvaluator.evaluate("true", %{})
    end

    test "string 'false' evaluates to false" do
      assert {:ok, false} = ConditionEvaluator.evaluate("false", %{})
    end

    test "boolean true evaluates to true" do
      assert {:ok, true} = ConditionEvaluator.evaluate(true, %{})
    end

    test "boolean false evaluates to false" do
      assert {:ok, false} = ConditionEvaluator.evaluate(false, %{})
    end

    test "nil evaluates to true (permissive default)" do
      assert {:ok, true} = ConditionEvaluator.evaluate(nil, %{})
    end

    test "empty string evaluates to true (permissive default)" do
      assert {:ok, true} = ConditionEvaluator.evaluate("", %{})
    end

    test "whitespace-only 'true' still evaluates correctly" do
      assert {:ok, true} = ConditionEvaluator.evaluate("  true  ", %{})
    end

    test "whitespace-only 'false' still evaluates correctly" do
      assert {:ok, false} = ConditionEvaluator.evaluate("  false  ", %{})
    end
  end

  # ============================================================================
  # Parameter Conditions
  # ============================================================================

  describe "evaluate/2 with params.* conditions" do
    test "params.key == value comparison" do
      context = build_context(params: %{"mode" => "nominal"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.mode == \"nominal\"", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.mode == \"safe\"", context)
    end

    test "params.key != value comparison" do
      context = build_context(params: %{"mode" => "nominal"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.mode != \"safe\"", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.mode != \"nominal\"", context)
    end

    test "params numeric greater than" do
      context = build_context(params: %{"threshold" => 75})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold > 50", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.threshold > 100", context)
    end

    test "params numeric greater than or equal" do
      context = build_context(params: %{"threshold" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold >= 50", context)
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold >= 49", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.threshold >= 51", context)
    end

    test "params numeric less than" do
      context = build_context(params: %{"threshold" => 25})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold < 50", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.threshold < 10", context)
    end

    test "params numeric less than or equal" do
      context = build_context(params: %{"threshold" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold <= 50", context)
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold <= 51", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.threshold <= 49", context)
    end

    test "params with nested path" do
      context = build_context(params: %{"config" => %{"level" => 3}})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.config.level > 2", context)
    end

    test "params with float values" do
      context = build_context(params: %{"ratio" => 0.75})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.ratio >= 0.5", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.ratio >= 0.8", context)
    end

    test "params with boolean values" do
      context = build_context(params: %{"enabled" => true})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.enabled == true", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("params.enabled == false", context)
    end

    test "missing param returns error" do
      context = build_context(params: %{})
      assert {:error, {:param_not_found, "missing"}} =
               ConditionEvaluator.evaluate("params.missing > 0", context)
    end

    test "missing nested param returns error" do
      context = build_context(params: %{"config" => %{}})
      assert {:error, {:param_not_found, "config.missing"}} =
               ConditionEvaluator.evaluate("params.config.missing > 0", context)
    end

    test "nil params map treated as empty" do
      context = %{params: nil}
      assert {:error, {:param_not_found, "key"}} =
               ConditionEvaluator.evaluate("params.key > 0", context)
    end
  end

  # ============================================================================
  # Variable Conditions
  # ============================================================================

  describe "evaluate/2 with vars.* conditions" do
    test "vars.step_name.result comparison" do
      context = build_context(vars: %{"init" => %{"result" => 42}})
      assert {:ok, true} = ConditionEvaluator.evaluate("vars.init.result == 42", context)
      assert {:ok, false} = ConditionEvaluator.evaluate("vars.init.result == 0", context)
    end

    test "vars numeric comparison" do
      context = build_context(vars: %{"calc" => %{"value" => 100}})
      assert {:ok, true} = ConditionEvaluator.evaluate("vars.calc.value >= 50", context)
    end

    test "missing var returns false (not error)" do
      # Unlike params, vars may not exist yet - treat as false
      context = build_context(vars: %{})
      assert {:ok, false} = ConditionEvaluator.evaluate("vars.missing.result == true", context)
    end

    test "nil vars map treated as empty" do
      context = %{vars: nil}
      assert {:ok, false} = ConditionEvaluator.evaluate("vars.step.result > 0", context)
    end
  end

  # ============================================================================
  # Telemetry Conditions (without real CVT)
  # ============================================================================

  describe "evaluate/2 with telemetry.* conditions" do
    # Note: These tests verify parsing and structure, not actual CVT lookup.
    # The CVT lookup will fail with :not_found in tests without mocking.

    test "telemetry condition format is recognized" do
      context = build_context()

      # Will fail at CVT lookup, but should parse correctly
      result = ConditionEvaluator.evaluate("telemetry.HK.battery_voltage >= 24", context)

      # Should be a telemetry lookup error, not a parse error
      assert {:error, {:telemetry_lookup_failed, _, _}} = result
    end

    test "telemetry with target prefix format" do
      context = build_context(target_id: "sat-01")

      result = ConditionEvaluator.evaluate("telemetry.SAT1.HK.voltage >= 24", context)
      assert {:error, {:telemetry_lookup_failed, _, _}} = result
    end

    test "telemetry with all comparison operators" do
      context = build_context()

      for op <- [">=", "<=", ">", "<", "==", "!="] do
        result = ConditionEvaluator.evaluate("telemetry.PKT.item #{op} 10", context)
        assert {:error, {:telemetry_lookup_failed, _, _}} = result
      end
    end
  end

  # ============================================================================
  # Generic Comparisons (no prefix)
  # ============================================================================

  describe "evaluate/2 with generic comparisons" do
    test "simple numeric comparison" do
      context = build_context(params: %{"x" => 10})

      # Generic comparison that resolves params
      result = ConditionEvaluator.evaluate("params.x >= 5", context)
      assert {:ok, true} = result
    end

    test "unresolvable left side treated as string literal" do
      context = build_context()

      # When left side can't be resolved (no telemetry./params./vars. prefix),
      # it's treated as a string literal. "unknown_var" >= 10 is false
      # because string-to-number comparison fails in compare_values_fallback.
      result = ConditionEvaluator.evaluate("unknown_var >= 10", context)
      assert {:ok, false} = result
    end
  end

  # ============================================================================
  # Operator Edge Cases
  # ============================================================================

  describe "comparison operators" do
    test ">= with equal values" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val >= 50", context)
    end

    test "<= with equal values" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val <= 50", context)
    end

    test "> with equal values returns false" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, false} = ConditionEvaluator.evaluate("params.val > 50", context)
    end

    test "< with equal values returns false" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, false} = ConditionEvaluator.evaluate("params.val < 50", context)
    end

    test "== with identical values" do
      context = build_context(params: %{"val" => "test"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == \"test\"", context)
    end

    test "!= with different values" do
      context = build_context(params: %{"val" => "test"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val != \"other\"", context)
    end

    test "!= with identical values returns false" do
      context = build_context(params: %{"val" => "test"})
      assert {:ok, false} = ConditionEvaluator.evaluate("params.val != \"test\"", context)
    end
  end

  # ============================================================================
  # Type Coercion
  # ============================================================================

  describe "type coercion" do
    test "string number compared to integer" do
      context = build_context(params: %{"val" => "50"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val >= 50", context)
    end

    test "integer compared to float" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val >= 49.5", context)
    end

    test "float compared to integer" do
      context = build_context(params: %{"val" => 50.5})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val > 50", context)
    end

    test "string-to-string equality" do
      context = build_context(params: %{"mode" => "test"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.mode == \"test\"", context)
    end

    test "numeric comparison with non-numeric string returns false" do
      context = build_context(params: %{"val" => "abc"})
      # Non-numeric comparison should return false for >, <, >=, <=
      assert {:ok, false} = ConditionEvaluator.evaluate("params.val >= 50", context)
    end
  end

  # ============================================================================
  # Value Parsing
  # ============================================================================

  describe "value parsing in conditions" do
    test "parses integer values" do
      context = build_context(params: %{"val" => 100})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == 100", context)
    end

    test "parses negative integer values" do
      context = build_context(params: %{"val" => -10})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == -10", context)
    end

    test "parses float values" do
      context = build_context(params: %{"val" => 3.14})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == 3.14", context)
    end

    test "parses negative float values" do
      context = build_context(params: %{"val" => -3.14})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == -3.14", context)
    end

    test "parses double-quoted strings" do
      context = build_context(params: %{"val" => "hello"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == \"hello\"", context)
    end

    test "parses single-quoted strings" do
      context = build_context(params: %{"val" => "hello"})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == 'hello'", context)
    end

    test "parses boolean true" do
      context = build_context(params: %{"val" => true})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == true", context)
    end

    test "parses boolean false" do
      context = build_context(params: %{"val" => false})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val == false", context)
    end

    test "parses nil in expected value" do
      # Note: A param with value nil is considered "not found" by the evaluator.
      # This test verifies that nil as the expected value parses correctly,
      # using a non-nil actual value to avoid the "not found" case.
      context = build_context(params: %{"val" => "something"})
      assert {:ok, false} = ConditionEvaluator.evaluate("params.val == nil", context)
    end

    test "param with nil value is considered not found" do
      # This is by design - nil values are treated as missing params
      context = build_context(params: %{"val" => nil})
      assert {:error, {:param_not_found, "val"}} =
               ConditionEvaluator.evaluate("params.val == nil", context)
    end
  end

  # ============================================================================
  # Error Handling
  # ============================================================================

  describe "error handling" do
    test "unknown condition format returns error" do
      context = build_context()

      assert {:error, {:unknown_condition_format, "gibberish_without_operator"}} =
               ConditionEvaluator.evaluate("gibberish_without_operator", context)
    end

    test "condition without operator returns error" do
      context = build_context()

      # The evaluator correctly identifies it as params.* but can't find an operator
      assert {:error, {:no_operator_found, _}} =
               ConditionEvaluator.evaluate("params.value", context)
    end

    test "non-string condition returns error" do
      context = build_context()

      assert {:error, {:invalid_condition_type, 123}} =
               ConditionEvaluator.evaluate(123, context)

      assert {:error, {:invalid_condition_type, []}} =
               ConditionEvaluator.evaluate([], context)

      assert {:error, {:invalid_condition_type, %{}}} =
               ConditionEvaluator.evaluate(%{}, context)
    end

    test "malformed params path returns error" do
      context = build_context(params: %{})

      result = ConditionEvaluator.evaluate("params. >= 10", context)
      # Should fail to find the empty param
      assert {:error, _} = result
    end
  end

  # ============================================================================
  # Context Edge Cases
  # ============================================================================

  describe "context edge cases" do
    test "empty context map" do
      assert {:ok, true} = ConditionEvaluator.evaluate("true", %{})
    end

    test "context with atom keys for params" do
      # Some contexts might have atom keys
      context = %{params: %{threshold: 50}}
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold >= 50", context)
    end

    test "context with mixed atom and string keys" do
      context = %{params: %{"threshold" => 50, enabled: true}}
      assert {:ok, true} = ConditionEvaluator.evaluate("params.threshold >= 50", context)
      assert {:ok, true} = ConditionEvaluator.evaluate("params.enabled == true", context)
    end

    test "deeply nested params" do
      context = build_context(
        params: %{
          "level1" => %{
            "level2" => %{
              "level3" => 42
            }
          }
        }
      )

      assert {:ok, true} =
               ConditionEvaluator.evaluate("params.level1.level2.level3 == 42", context)
    end

    test "deeply nested vars" do
      context = build_context(
        vars: %{
          "step1" => %{
            "result" => %{
              "nested" => "value"
            }
          }
        }
      )

      assert {:ok, true} =
               ConditionEvaluator.evaluate("vars.step1.result.nested == \"value\"", context)
    end
  end

  # ============================================================================
  # Whitespace Handling
  # ============================================================================

  describe "whitespace handling" do
    test "extra whitespace around operator" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val   >=   50", context)
    end

    test "leading and trailing whitespace" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("   params.val >= 50   ", context)
    end

    test "no whitespace around operator" do
      context = build_context(params: %{"val" => 50})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.val>=50", context)
    end
  end

  # ============================================================================
  # Real-World Condition Examples
  # ============================================================================

  describe "real-world condition examples" do
    test "battery voltage check" do
      context = build_context(params: %{"min_voltage" => 24.0})
      # Would typically compare against telemetry, but we can test params
      assert {:ok, true} = ConditionEvaluator.evaluate("params.min_voltage >= 22.0", context)
    end

    test "mode check" do
      context = build_context(params: %{"spacecraft_mode" => "nominal"})
      assert {:ok, true} =
               ConditionEvaluator.evaluate("params.spacecraft_mode == \"nominal\"", context)
    end

    test "threshold with step result" do
      context = build_context(
        params: %{"threshold" => 100},
        vars: %{"measure" => %{"value" => 150}}
      )
      assert {:ok, true} = ConditionEvaluator.evaluate("vars.measure.value >= 100", context)
    end

    test "boolean flag check" do
      context = build_context(params: %{"safe_mode" => false})
      assert {:ok, true} = ConditionEvaluator.evaluate("params.safe_mode == false", context)
    end
  end
end
