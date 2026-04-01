defmodule Cadence.Telemetry.DerivedItems.ExpressionEvaluatorTest do
  @moduledoc """
  Unit tests for the safe expression evaluator.

  Tests tokenization, parsing, and evaluation of mathematical expressions
  with variable substitution for derived telemetry items.

  All variable names must be qualified in PACKET.ITEM format.
  """

  use ExUnit.Case, async: true

  alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator

  describe "basic arithmetic" do
    test "evaluates addition" do
      assert {:ok, 5} = ExpressionEvaluator.evaluate("2 + 3", %{})
    end

    test "evaluates subtraction" do
      assert {:ok, 7} = ExpressionEvaluator.evaluate("10 - 3", %{})
    end

    test "evaluates multiplication" do
      assert {:ok, 12} = ExpressionEvaluator.evaluate("3 * 4", %{})
    end

    test "evaluates division" do
      assert {:ok, 2.5} = ExpressionEvaluator.evaluate("5 / 2", %{})
    end

    test "handles operator precedence" do
      # Multiplication before addition
      assert {:ok, 11} = ExpressionEvaluator.evaluate("2 + 3 * 3", %{})
    end

    test "handles parentheses" do
      # Parentheses override precedence
      assert {:ok, 15} = ExpressionEvaluator.evaluate("(2 + 3) * 3", %{})
    end

    test "handles nested parentheses" do
      assert {:ok, 20} = ExpressionEvaluator.evaluate("((2 + 3) * 2) * 2", %{})
    end

    test "handles negative numbers with unary minus" do
      assert {:ok, -5} = ExpressionEvaluator.evaluate("-5", %{})
    end

    test "handles unary minus in expressions" do
      assert {:ok, 2} = ExpressionEvaluator.evaluate("5 + -3", %{})
    end

    test "handles unary minus in parentheses" do
      assert {:ok, -15} = ExpressionEvaluator.evaluate("-(3 * 5)", %{})
    end
  end

  describe "decimal numbers" do
    test "evaluates decimal literals" do
      assert {:ok, 3.14} = ExpressionEvaluator.evaluate("3.14", %{})
    end

    test "evaluates expressions with decimals" do
      {:ok, result} = ExpressionEvaluator.evaluate("1.5 + 2.5", %{})
      assert_in_delta result, 4.0, 0.001
    end

    test "handles zero as decimal" do
      {:ok, result} = ExpressionEvaluator.evaluate("0.5 + 0.5", %{})
      assert_in_delta result, 1.0, 0.001
    end
  end

  describe "variable substitution with qualified names" do
    test "evaluates single qualified variable" do
      bindings = %{"HEALTH.TEMP" => 25.0}
      assert {:ok, 25.0} = ExpressionEvaluator.evaluate("HEALTH.TEMP", bindings)
    end

    test "evaluates expression with qualified variables" do
      bindings = %{"HEALTH.TEMP1" => 25.0, "HEALTH.TEMP2" => 30.0}
      {:ok, result} = ExpressionEvaluator.evaluate("HEALTH.TEMP1 + HEALTH.TEMP2", bindings)
      assert_in_delta result, 55.0, 0.001
    end

    test "handles mixed variables and constants" do
      bindings = %{"POWER.VOLTAGE" => 28.0, "POWER.CURRENT" => 5.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate("(POWER.VOLTAGE * POWER.CURRENT) / 1000", bindings)

      assert_in_delta result, 0.14, 0.001
    end

    test "handles underscores in qualified variable names" do
      bindings = %{"HEALTH.cpu_temp" => 42.0}
      assert {:ok, 42.0} = ExpressionEvaluator.evaluate("HEALTH.cpu_temp", bindings)
    end

    test "handles numbers in qualified variable names" do
      bindings = %{"SENSOR.TEMP1" => 10.0, "SENSOR.TEMP2" => 20.0}
      {:ok, result} = ExpressionEvaluator.evaluate("SENSOR.TEMP1 + SENSOR.TEMP2", bindings)
      assert_in_delta result, 30.0, 0.001
    end

    test "handles cross-packet references" do
      bindings = %{"HEALTH.TEMP" => 25.0, "POWER.VOLTAGE" => 12.0}
      {:ok, result} = ExpressionEvaluator.evaluate("HEALTH.TEMP + POWER.VOLTAGE", bindings)
      assert_in_delta result, 37.0, 0.001
    end

    test "returns error for undefined qualified variable" do
      assert {:error, {:undefined_variable, "HEALTH.MISSING"}} =
               ExpressionEvaluator.evaluate("HEALTH.MISSING + 1", %{})
    end

    test "returns error for non-numeric variable value" do
      bindings = %{"HEALTH.STATUS" => "OK"}

      assert {:error, {:non_numeric_value, "HEALTH.STATUS", "OK"}} =
               ExpressionEvaluator.evaluate("HEALTH.STATUS + 1", bindings)
    end

    test "returns error for nil variable value" do
      bindings = %{"HEALTH.TEMP" => nil}

      assert {:error, {:nil_value, "HEALTH.TEMP"}} =
               ExpressionEvaluator.evaluate("HEALTH.TEMP + 1", bindings)
    end
  end

  describe "unqualified variable rejection" do
    test "rejects single unqualified variable" do
      assert {:error, {:unqualified_variable, "TEMP"}} =
               ExpressionEvaluator.evaluate("TEMP", %{})
    end

    test "rejects unqualified variable in expression" do
      assert {:error, {:unqualified_variable, "TEMP1"}} =
               ExpressionEvaluator.evaluate("TEMP1 + TEMP2", %{})
    end

    test "rejects mixed qualified and unqualified variables" do
      result = ExpressionEvaluator.evaluate("HEALTH.TEMP + UNQUALIFIED", %{})
      assert {:error, {:unqualified_variable, "UNQUALIFIED"}} = result
    end

    test "rejects variable with underscore but no qualifier" do
      assert {:error, {:unqualified_variable, "cpu_temp"}} =
               ExpressionEvaluator.evaluate("cpu_temp + 1", %{})
    end
  end

  describe "functions - single argument" do
    test "abs returns absolute value of positive" do
      assert {:ok, 5} = ExpressionEvaluator.evaluate("abs(5)", %{})
    end

    test "abs returns absolute value of negative" do
      assert {:ok, 5} = ExpressionEvaluator.evaluate("abs(-5)", %{})
    end

    test "abs with variable" do
      bindings = %{"HEALTH.TEMP" => -15.0}
      assert {:ok, 15.0} = ExpressionEvaluator.evaluate("abs(HEALTH.TEMP)", bindings)
    end

    test "sqrt returns square root" do
      assert {:ok, 4.0} = ExpressionEvaluator.evaluate("sqrt(16)", %{})
    end

    test "sqrt with variable" do
      bindings = %{"MATH.X" => 25.0}
      assert {:ok, 5.0} = ExpressionEvaluator.evaluate("sqrt(MATH.X)", bindings)
    end

    test "sqrt returns error for negative" do
      assert {:error, {:domain_error, :sqrt, -1}} =
               ExpressionEvaluator.evaluate("sqrt(-1)", %{})
    end

    test "round rounds to nearest integer" do
      assert {:ok, 3} = ExpressionEvaluator.evaluate("round(3.4)", %{})
      assert {:ok, 4} = ExpressionEvaluator.evaluate("round(3.6)", %{})
    end

    test "floor rounds down" do
      assert {:ok, 3} = ExpressionEvaluator.evaluate("floor(3.9)", %{})
      assert {:ok, -4} = ExpressionEvaluator.evaluate("floor(-3.1)", %{})
    end

    test "ceil rounds up" do
      assert {:ok, 4} = ExpressionEvaluator.evaluate("ceil(3.1)", %{})
      assert {:ok, -3} = ExpressionEvaluator.evaluate("ceil(-3.9)", %{})
    end
  end

  describe "functions - multiple arguments" do
    test "pow computes exponentiation" do
      assert {:ok, 8.0} = ExpressionEvaluator.evaluate("pow(2, 3)", %{})
    end

    test "pow with variables" do
      bindings = %{"MATH.BASE" => 2.0, "MATH.EXP" => 10.0}
      assert {:ok, 1024.0} = ExpressionEvaluator.evaluate("pow(MATH.BASE, MATH.EXP)", bindings)
    end

    test "min returns minimum of two values" do
      assert {:ok, 2} = ExpressionEvaluator.evaluate("min(2, 5)", %{})
    end

    test "min returns minimum of multiple values" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("min(3, 1, 4, 2)", %{})
    end

    test "min with variables" do
      bindings = %{"THERMAL.T1" => 25.0, "THERMAL.T2" => 30.0, "THERMAL.T3" => 20.0}

      assert {:ok, 20.0} =
               ExpressionEvaluator.evaluate("min(THERMAL.T1, THERMAL.T2, THERMAL.T3)", bindings)
    end

    test "max returns maximum of two values" do
      assert {:ok, 5} = ExpressionEvaluator.evaluate("max(2, 5)", %{})
    end

    test "max returns maximum of multiple values" do
      assert {:ok, 4} = ExpressionEvaluator.evaluate("max(3, 1, 4, 2)", %{})
    end

    test "max with variables" do
      bindings = %{"THERMAL.T1" => 25.0, "THERMAL.T2" => 30.0, "THERMAL.T3" => 20.0}

      assert {:ok, 30.0} =
               ExpressionEvaluator.evaluate("max(THERMAL.T1, THERMAL.T2, THERMAL.T3)", bindings)
    end

    test "clamp constrains value to range" do
      assert {:ok, 50} = ExpressionEvaluator.evaluate("clamp(50, 0, 100)", %{})
    end

    test "clamp returns min when below range" do
      assert {:ok, 0} = ExpressionEvaluator.evaluate("clamp(-10, 0, 100)", %{})
    end

    test "clamp returns max when above range" do
      assert {:ok, 100} = ExpressionEvaluator.evaluate("clamp(150, 0, 100)", %{})
    end

    test "clamp with variables" do
      bindings = %{"HEALTH.TEMP" => 150.0}
      {:ok, result} = ExpressionEvaluator.evaluate("clamp(HEALTH.TEMP, 0, 100)", bindings)
      assert_in_delta result, 100.0, 0.001
    end
  end

  describe "functions - error handling" do
    test "unknown function returns error" do
      assert {:error, {:unknown_function, :unknown}} =
               ExpressionEvaluator.evaluate("unknown(1)", %{})
    end

    test "abs with wrong arity returns error" do
      assert {:error, {:invalid_arity, :abs, 1, 2}} =
               ExpressionEvaluator.evaluate("abs(1, 2)", %{})
    end

    test "sqrt with wrong arity returns error" do
      assert {:error, {:invalid_arity, :sqrt, 1, 0}} =
               ExpressionEvaluator.evaluate("sqrt()", %{})
    end

    test "min requires at least 2 arguments" do
      assert {:error, {:invalid_arity, :min, "2+", 1}} =
               ExpressionEvaluator.evaluate("min(1)", %{})
    end

    test "clamp requires exactly 3 arguments" do
      assert {:error, {:invalid_arity, :clamp, 3, 2}} =
               ExpressionEvaluator.evaluate("clamp(1, 2)", %{})
    end
  end

  describe "functions - nested" do
    test "nested function calls" do
      assert {:ok, 4.0} = ExpressionEvaluator.evaluate("sqrt(abs(-16))", %{})
    end

    test "function with expression argument" do
      bindings = %{"HEALTH.T1" => 25.0, "HEALTH.T2" => 30.0}
      {:ok, result} = ExpressionEvaluator.evaluate("abs(HEALTH.T1 - HEALTH.T2)", bindings)
      assert_in_delta result, 5.0, 0.001
    end

    test "function in larger expression" do
      bindings = %{"HEALTH.TEMP" => -10.0}
      {:ok, result} = ExpressionEvaluator.evaluate("abs(HEALTH.TEMP) + 5", bindings)
      assert_in_delta result, 15.0, 0.001
    end
  end

  describe "comparison operators" do
    test "less than - true" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("5 < 10", %{})
    end

    test "less than - false" do
      assert {:ok, 0} = ExpressionEvaluator.evaluate("10 < 5", %{})
    end

    test "greater than - true" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("10 > 5", %{})
    end

    test "greater than - false" do
      assert {:ok, 0} = ExpressionEvaluator.evaluate("5 > 10", %{})
    end

    test "less than or equal - true" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("5 <= 5", %{})
      assert {:ok, 1} = ExpressionEvaluator.evaluate("4 <= 5", %{})
    end

    test "greater than or equal - true" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("5 >= 5", %{})
      assert {:ok, 1} = ExpressionEvaluator.evaluate("6 >= 5", %{})
    end

    test "equal - true" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("5 == 5", %{})
    end

    test "equal - false" do
      assert {:ok, 0} = ExpressionEvaluator.evaluate("5 == 6", %{})
    end

    test "not equal - true" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("5 != 6", %{})
    end

    test "not equal - false" do
      assert {:ok, 0} = ExpressionEvaluator.evaluate("5 != 5", %{})
    end

    test "comparison with variables" do
      bindings = %{"POWER.VOLTAGE" => 10.5}
      assert {:ok, 1} = ExpressionEvaluator.evaluate("POWER.VOLTAGE < 11.0", bindings)
    end
  end

  describe "conditionals" do
    test "if-then-else with true condition" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("if 1 then 1 else 0", %{})
    end

    test "if-then-else with false condition" do
      assert {:ok, 0} = ExpressionEvaluator.evaluate("if 0 then 1 else 0", %{})
    end

    test "if-then-else with comparison" do
      bindings = %{"POWER.VOLTAGE" => 10.5}

      assert {:ok, 1} =
               ExpressionEvaluator.evaluate("if POWER.VOLTAGE < 11.0 then 1 else 0", bindings)
    end

    test "if-then-else with comparison - else branch" do
      bindings = %{"POWER.VOLTAGE" => 12.0}

      assert {:ok, 0} =
               ExpressionEvaluator.evaluate("if POWER.VOLTAGE < 11.0 then 1 else 0", bindings)
    end

    test "if-then-else with expressions in branches" do
      bindings = %{"HEALTH.TEMP" => 75.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate(
          "if HEALTH.TEMP > 50 then HEALTH.TEMP * 2 else HEALTH.TEMP / 2",
          bindings
        )

      assert_in_delta result, 150.0, 0.001
    end

    test "nested conditionals" do
      bindings = %{"HEALTH.TEMP" => 75.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate(
          "if HEALTH.TEMP > 100 then 3 else if HEALTH.TEMP > 50 then 2 else 1",
          bindings
        )

      assert result == 2
    end

    test "conditional with function in condition" do
      bindings = %{"HEALTH.TEMP" => -15.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate(
          "if abs(HEALTH.TEMP) > 10 then 1 else 0",
          bindings
        )

      assert result == 1
    end
  end

  describe "complex expressions" do
    test "computes average of two values" do
      bindings = %{"HEALTH.TEMP1" => 20.0, "HEALTH.TEMP2" => 30.0}
      {:ok, result} = ExpressionEvaluator.evaluate("(HEALTH.TEMP1 + HEALTH.TEMP2) / 2", bindings)
      assert_in_delta result, 25.0, 0.001
    end

    test "computes temperature conversion (C to F)" do
      bindings = %{"HEALTH.TEMP_C" => 25.0}
      {:ok, result} = ExpressionEvaluator.evaluate("HEALTH.TEMP_C * 1.8 + 32", bindings)
      assert_in_delta result, 77.0, 0.001
    end

    test "computes power calculation" do
      bindings = %{"POWER.VOLTAGE" => 12.0, "POWER.CURRENT" => 2.5}
      {:ok, result} = ExpressionEvaluator.evaluate("POWER.VOLTAGE * POWER.CURRENT", bindings)
      assert_in_delta result, 30.0, 0.001
    end

    test "handles deeply nested expressions" do
      bindings = %{"CALC.A" => 1.0, "CALC.B" => 2.0, "CALC.C" => 3.0}

      {:ok, result} =
        ExpressionEvaluator.evaluate("((CALC.A + CALC.B) * (CALC.B + CALC.C)) / 2", bindings)

      # ((1+2) * (2+3)) / 2 = (3 * 5) / 2 = 7.5
      assert_in_delta result, 7.5, 0.001
    end

    test "realistic thermal protection expression" do
      bindings = %{
        "THERMAL.TEMP1" => 85.0,
        "THERMAL.TEMP2" => 90.0,
        "THERMAL.TEMP3" => 88.0
      }

      # Return 1 (warning) if max temp > 80, else 0
      {:ok, result} =
        ExpressionEvaluator.evaluate(
          "if max(THERMAL.TEMP1, THERMAL.TEMP2, THERMAL.TEMP3) > 80 then 1 else 0",
          bindings
        )

      assert result == 1
    end

    test "battery state of charge calculation" do
      bindings = %{
        "POWER.VOLTAGE" => 12.0,
        "POWER.V_MIN" => 10.0,
        "POWER.V_MAX" => 14.0
      }

      # SOC% = clamp((V - Vmin) / (Vmax - Vmin) * 100, 0, 100)
      {:ok, result} =
        ExpressionEvaluator.evaluate(
          "clamp((POWER.VOLTAGE - POWER.V_MIN) / (POWER.V_MAX - POWER.V_MIN) * 100, 0, 100)",
          bindings
        )

      assert_in_delta result, 50.0, 0.001
    end
  end

  describe "error handling" do
    test "returns error for division by zero" do
      assert {:error, :division_by_zero} = ExpressionEvaluator.evaluate("10 / 0", %{})
    end

    test "returns error for variable division by zero" do
      bindings = %{"MATH.X" => 0}
      assert {:error, :division_by_zero} = ExpressionEvaluator.evaluate("10 / MATH.X", bindings)
    end

    test "returns error for parse error on invalid syntax" do
      # NimbleParsec gives parse errors for invalid syntax
      assert {:error, _} = ExpressionEvaluator.evaluate("10 @ 5", %{})
    end

    test "returns error for unclosed parenthesis" do
      assert {:error, _} = ExpressionEvaluator.evaluate("(10 + 5", %{})
    end

    test "returns error for trailing operator" do
      assert {:error, _} = ExpressionEvaluator.evaluate("10 +", %{})
    end

    test "returns error for empty expression" do
      assert {:error, _} = ExpressionEvaluator.evaluate("", %{})
    end
  end

  describe "validate/1" do
    test "validates correct expression with qualified names" do
      assert :ok = ExpressionEvaluator.validate("HEALTH.TEMP1 + HEALTH.TEMP2")
    end

    test "validates complex expression with qualified names" do
      assert :ok = ExpressionEvaluator.validate("((CALC.A + CALC.B) * CALC.C) / 2")
    end

    test "validates expression with functions" do
      assert :ok = ExpressionEvaluator.validate("abs(HEALTH.TEMP - 20)")
    end

    test "validates expression with conditionals" do
      assert :ok = ExpressionEvaluator.validate("if POWER.VOLTAGE < 11.0 then 1 else 0")
    end

    test "returns error for invalid expression" do
      assert {:error, _} = ExpressionEvaluator.validate("HEALTH.TEMP +")
    end

    test "returns error for unqualified variable" do
      assert {:error, {:unqualified_variable, "TEMP"}} = ExpressionEvaluator.validate("TEMP + 1")
    end
  end

  describe "extract_variables/1" do
    test "extracts single qualified variable" do
      assert {:ok, ["HEALTH.TEMP"]} = ExpressionEvaluator.extract_variables("HEALTH.TEMP")
    end

    test "extracts multiple qualified variables" do
      {:ok, vars} = ExpressionEvaluator.extract_variables("HEALTH.TEMP1 + HEALTH.TEMP2")
      assert Enum.sort(vars) == ["HEALTH.TEMP1", "HEALTH.TEMP2"]
    end

    test "extracts cross-packet variables" do
      {:ok, vars} = ExpressionEvaluator.extract_variables("HEALTH.TEMP + POWER.VOLTAGE")
      assert Enum.sort(vars) == ["HEALTH.TEMP", "POWER.VOLTAGE"]
    end

    test "returns unique variables" do
      {:ok, vars} = ExpressionEvaluator.extract_variables("HEALTH.TEMP + HEALTH.TEMP")
      assert vars == ["HEALTH.TEMP"]
    end

    test "ignores numeric literals" do
      {:ok, vars} = ExpressionEvaluator.extract_variables("HEALTH.TEMP * 1.8 + 32")
      assert vars == ["HEALTH.TEMP"]
    end

    test "returns empty list for constants only" do
      assert {:ok, []} = ExpressionEvaluator.extract_variables("10 + 20")
    end

    test "extracts variables from function arguments" do
      {:ok, vars} = ExpressionEvaluator.extract_variables("abs(HEALTH.TEMP - POWER.OFFSET)")
      assert Enum.sort(vars) == ["HEALTH.TEMP", "POWER.OFFSET"]
    end

    test "extracts variables from conditionals" do
      {:ok, vars} =
        ExpressionEvaluator.extract_variables(
          "if POWER.VOLTAGE < 11.0 then HEALTH.WARN else HEALTH.OK"
        )

      assert Enum.sort(vars) == ["HEALTH.OK", "HEALTH.WARN", "POWER.VOLTAGE"]
    end

    test "returns error for unqualified variable" do
      assert {:error, {:unqualified_variable, "TEMP"}} =
               ExpressionEvaluator.extract_variables("TEMP + 1")
    end
  end

  describe "whitespace handling" do
    test "handles expression without spaces" do
      {:ok, result} = ExpressionEvaluator.evaluate("2+3*4", %{})
      assert result == 14
    end

    test "handles expression with extra spaces" do
      {:ok, result} = ExpressionEvaluator.evaluate("  2  +  3  ", %{})
      assert result == 5
    end

    test "handles tabs and newlines" do
      {:ok, result} = ExpressionEvaluator.evaluate("2\t+\n3", %{})
      assert result == 5
    end

    test "handles whitespace around qualified variables" do
      bindings = %{"HEALTH.TEMP" => 10.0}
      {:ok, result} = ExpressionEvaluator.evaluate("  HEALTH.TEMP  +  5  ", bindings)
      assert_in_delta result, 15.0, 0.001
    end

    test "handles whitespace in function calls" do
      assert {:ok, 5} = ExpressionEvaluator.evaluate("abs( -5 )", %{})
    end

    test "handles whitespace in conditionals" do
      assert {:ok, 1} = ExpressionEvaluator.evaluate("if  1  then  1  else  0", %{})
    end
  end

  describe "format_error/1" do
    test "formats undefined variable error" do
      msg = ExpressionEvaluator.format_error({:undefined_variable, "HEALTH.TEMP"})
      assert msg == "Undefined variable: HEALTH.TEMP"
    end

    test "formats nil value error" do
      msg = ExpressionEvaluator.format_error({:nil_value, "HEALTH.TEMP"})
      assert msg == "Variable has nil value: HEALTH.TEMP"
    end

    test "formats division by zero error" do
      msg = ExpressionEvaluator.format_error(:division_by_zero)
      assert msg == "Division by zero"
    end

    test "formats unknown function error" do
      msg = ExpressionEvaluator.format_error({:unknown_function, :foo})
      assert msg =~ "Unknown function: foo"
      assert msg =~ "Supported pure functions"
      assert msg =~ "Supported stateful functions"
    end

    test "formats invalid arity error" do
      msg = ExpressionEvaluator.format_error({:invalid_arity, :abs, 1, 2})
      assert msg == "Function abs expects 1 argument(s), got 2"
    end

    test "formats domain error for sqrt" do
      msg = ExpressionEvaluator.format_error({:domain_error, :sqrt, -5})
      assert msg =~ "Cannot compute square root of negative number"
      assert msg =~ "-5"
    end

    test "formats unqualified variable error" do
      msg = ExpressionEvaluator.format_error({:unqualified_variable, "TEMP"})
      assert msg =~ "Unqualified variable: TEMP"
      assert msg =~ "PACKET.ITEM format"
    end

    test "formats parse error" do
      msg = ExpressionEvaluator.format_error({:parse_error, "expected number", "@ 5", 1, 4})
      assert msg =~ "Parse error"
      assert msg =~ "position 4"
    end

    test "formats unexpected input error" do
      msg = ExpressionEvaluator.format_error({:unexpected_input, "garbage"})
      assert msg =~ "Unexpected input"
      assert msg =~ "garbage"
    end

    test "formats missing expression error" do
      msg = ExpressionEvaluator.format_error(:missing_expression)
      assert msg == "Expression is empty or missing"
    end

    test "formats unknown error" do
      msg = ExpressionEvaluator.format_error({:some, :unknown, :error})
      assert msg =~ "Expression error"
    end
  end
end
