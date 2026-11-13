defmodule CadenceSimulator.Providers.DatabaseDynamics.RangesTest do
  use CadenceSimulator.Case, async: true

  alias CadenceSimulator.Providers.DatabaseDynamics.Ranges

  # The shape cadence_yaml imports produce since 52afebc0 (red critical, yellow warning).
  defp rule(operator, value, severity),
    do: %{kind: :comparison, operator: operator, value: value, severity: severity}

  describe "policy_limits/1" do
    test "reads default_rules comparisons as red and yellow thresholds" do
      policy = %{
        default_rules: [
          rule(:>, 30.0, :critical),
          rule(:<, 0.0, :critical),
          rule(:>, 20.0, :warning),
          rule(:<, 10.0, :warning)
        ]
      }

      assert Ranges.policy_limits(policy) == %{
               "red_high" => 30.0,
               "red_low" => 0.0,
               "yellow_high" => 20.0,
               "yellow_low" => 10.0
             }
    end

    test "reads string-keyed rules with string operators and severities (a stored plan)" do
      policy = %{
        "default_rules" => [
          %{"kind" => "comparison", "operator" => ">", "value" => 20, "severity" => "warning"},
          %{"kind" => "comparison", "operator" => "<", "value" => 10, "severity" => "warning"}
        ]
      }

      assert Ranges.policy_limits(policy) == %{"yellow_high" => 20, "yellow_low" => 10}
    end

    test "still reads the raw rules map of catalogs imported before default_rules" do
      assert Ranges.policy_limits(%{rules: %{"yellow_low" => 10.0, "yellow_high" => 20.0}}) ==
               %{"yellow_low" => 10.0, "yellow_high" => 20.0}
    end

    test "ignores rules that state no threshold" do
      policy = %{
        default_rules: [
          %{kind: :range, min: 0, max: 10, severity: :warning},
          %{kind: :enumerated, values: ["SAFE"], severity: :critical},
          rule(:==, 3, :warning),
          rule(:>, "high", :critical),
          rule(:>, 5, :info),
          :not_a_rule
        ]
      }

      assert Ranges.policy_limits(policy) == %{}
      assert Ranges.policy_limits(%{}) == %{}
    end
  end

  describe "limits_by_parameter/1" do
    test "maps each policy's parameter to its thresholds" do
      plan = %{
        "policies" => [
          %{"parameter_id" => "param-cpu-temp", "default_rules" => [rule(:>, 20.0, :warning)]},
          %{"parameter_id" => "param-volts", "rules" => %{"red_low" => 3.0}}
        ]
      }

      assert Ranges.limits_by_parameter(plan) == %{
               "param-cpu-temp" => %{"yellow_high" => 20.0},
               "param-volts" => %{"red_low" => 3.0}
             }
    end
  end

  describe "float_range/2" do
    test "takes red before yellow on each side" do
      limits = %{
        "red_low" => 0.0,
        "yellow_low" => 10.0,
        "yellow_high" => 20.0,
        "red_high" => 30.0
      }

      assert Ranges.float_range(limits, "cpu_temp") == {0.0, 30.0}
    end

    test "uses yellow thresholds when there are no red ones" do
      assert Ranges.float_range(%{"yellow_low" => 10.0, "yellow_high" => 20.0}, "cpu_temp") ==
               {10.0, 20.0}
    end

    test "fills a one-sided limit's missing side from the keyword range" do
      assert Ranges.float_range(%{"red_high" => 30.0}, "cpu_temp") == {-40.0, 30.0}
      assert Ranges.float_range(%{"yellow_low" => 5.0}, "bus_voltage") == {5.0, 50.0}
    end

    test "keeps low below high when a one-sided limit lies beyond the keyword range" do
      # temp keyword range is -40..85 (span 125).
      assert Ranges.float_range(%{"red_high" => -50.0}, "cpu_temp") == {-175.0, -50.0}
      assert Ranges.float_range(%{"red_low" => 90.0}, "cpu_temp") == {90.0, 215.0}
    end

    test "falls back to the keyword range, or 0..100, without limits" do
      assert Ranges.float_range(%{}, "cpu_temp") == {-40.0, 85.0}
      assert Ranges.float_range(%{}, "widget") == {0.0, 100.0}
    end
  end

  describe "int_range/3" do
    test "rounds both-sided limits" do
      assert Ranges.int_range(%{"yellow_low" => 9.6, "red_high" => 120.2}, 8, false) == {10, 120}
    end

    test "fills a one-sided limit's missing side from the encoding range" do
      assert Ranges.int_range(%{"red_high" => 100}, 8, false) == {0, 100}
      assert Ranges.int_range(%{"red_low" => -100}, 8, true) == {-100, 127}
    end

    test "keeps low below high when a one-sided limit lies beyond the encoding range" do
      assert Ranges.int_range(%{"red_low" => 300}, 8, false) == {300, 555}
    end

    test "falls back to the encoding range without limits" do
      assert Ranges.int_range(%{}, 8, false) == {0, 255}
      assert Ranges.int_range(%{}, 8, true) == {-128, 127}
      assert Ranges.int_range(%{}, nil, false) == {0, 1000}
    end
  end
end
