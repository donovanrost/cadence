defmodule Cadence.Procedures.Dag.ValidatorTest do
  use ExUnit.Case, async: true

  alias Cadence.Procedures.Dag.Validator

  describe "validate/1" do
    test "accepts valid DAG with no cycles" do
      steps = %{
        "step_a" => %{"type" => "log", "message" => "Hello"},
        "step_b" => %{"type" => "log", "message" => "World", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "message" => "Done", "depends_on" => ["step_a", "step_b"]}
      }

      assert :ok = Validator.validate(steps)
    end

    test "accepts DAG with parallel branches" do
      steps = %{
        "init" => %{"type" => "log", "message" => "Start"},
        "branch_a" => %{"type" => "wait", "duration" => 100, "depends_on" => ["init"]},
        "branch_b" => %{"type" => "wait", "duration" => 100, "depends_on" => ["init"]},
        "join" => %{
          "type" => "log",
          "message" => "Done",
          "depends_on" => ["branch_a", "branch_b"]
        }
      }

      assert :ok = Validator.validate(steps)
    end

    test "rejects DAG with direct cycle" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_b"]},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "Cycle detected"))
    end

    test "rejects DAG with indirect cycle" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_c"]},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "Cycle detected"))
    end

    test "rejects step with missing dependency" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["nonexistent"]}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "non-existent steps"))
    end

    test "rejects step missing type field" do
      steps = %{
        "step_a" => %{"message" => "Hello"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'type'"))
    end

    test "rejects empty step name" do
      steps = %{
        "" => %{"type" => "log", "message" => "Hello"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "cannot be empty"))
    end

    test "rejects reserved step names" do
      steps = %{
        "start" => %{"type" => "log", "message" => "Hello"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "Reserved step names"))
    end

    test "rejects invalid depends_on format" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => "step_b"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "must be a list"))
    end

    test "rejects non-map input" do
      assert {:error, ["Steps must be a map"]} = Validator.validate([])
    end

    test "accepts empty steps map" do
      assert :ok = Validator.validate(%{})
    end

    test "rejects step definition that is not a map" do
      steps = %{
        "step_a" => "not a map"
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "must be a map"))
    end

    test "rejects self-referential step" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "Cycle detected"))
    end

    test "detects longer cycle chains" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_d"]},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]},
        "step_d" => %{"type" => "log", "depends_on" => ["step_c"]}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "Cycle detected"))
    end
  end

  describe "step type validation" do
    test "command step requires 'name' field" do
      steps = %{
        "send_cmd" => %{"type" => "command"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "command"))
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'name'"))
    end

    test "command step with name is valid" do
      steps = %{
        "send_cmd" => %{"type" => "command", "name" => "POWER_ON"}
      }

      assert :ok = Validator.validate(steps)
    end

    test "wait step requires 'duration' field" do
      steps = %{
        "wait_step" => %{"type" => "wait"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "wait"))
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'duration'"))
    end

    test "wait step with integer duration is valid" do
      steps = %{
        "wait_step" => %{"type" => "wait", "duration" => 1000}
      }

      assert :ok = Validator.validate(steps)
    end

    test "wait step with string duration is valid" do
      steps = %{
        "wait_step" => %{"type" => "wait", "duration" => "{{params.delay}}"}
      }

      assert :ok = Validator.validate(steps)
    end

    test "wait step rejects invalid duration type" do
      steps = %{
        "wait_step" => %{"type" => "wait", "duration" => %{}}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "must be a number or string"))
    end

    test "wait_for step requires 'item' field" do
      steps = %{
        "wait_step" => %{"type" => "wait_for", "value" => 100}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'item'"))
    end

    test "wait_for step requires 'value' field" do
      steps = %{
        "wait_step" => %{"type" => "wait_for", "item" => "temperature"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'value'"))
    end

    test "wait_for step with both fields is valid" do
      steps = %{
        "wait_step" => %{"type" => "wait_for", "item" => "temperature", "value" => 100}
      }

      assert :ok = Validator.validate(steps)
    end

    test "check step requires 'condition' field" do
      steps = %{
        "check_step" => %{"type" => "check"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "check"))
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'condition'"))
    end

    test "check step with condition is valid" do
      steps = %{
        "check_step" => %{"type" => "check", "condition" => "temperature > 50"}
      }

      assert :ok = Validator.validate(steps)
    end

    test "assert step requires 'condition' field" do
      steps = %{
        "assert_step" => %{"type" => "assert"}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "assert"))
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'condition'"))
    end

    test "assert step with condition is valid" do
      steps = %{
        "assert_step" => %{"type" => "assert", "condition" => "1 == 1"}
      }

      assert :ok = Validator.validate(steps)
    end

    test "set step requires 'name' field (variable name)" do
      steps = %{
        "set_step" => %{"type" => "set", "value" => 42}
      }

      assert {:error, reasons} = Validator.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "set"))
      assert Enum.any?(reasons, &String.contains?(&1, "missing required field 'name'"))
    end

    test "set step with name is valid" do
      steps = %{
        "set_step" => %{"type" => "set", "name" => "my_var", "value" => 42}
      }

      assert :ok = Validator.validate(steps)
    end

    test "log step does not require message" do
      steps = %{
        "log_step" => %{"type" => "log"}
      }

      assert :ok = Validator.validate(steps)
    end

    test "unknown step type passes validation" do
      # Unknown types don't have additional validation
      steps = %{
        "custom_step" => %{"type" => "custom_type", "some_field" => "value"}
      }

      assert :ok = Validator.validate(steps)
    end
  end

  describe "dag_format?/1" do
    test "returns true for DAG format (steps as map)" do
      source = %{
        "steps" => %{
          "step_a" => %{"type" => "log"}
        }
      }

      assert Validator.dag_format?(source)
    end

    test "returns false for linear format (steps as list)" do
      source = %{
        "steps" => [
          %{"type" => "log", "message" => "Hello"}
        ]
      }

      refute Validator.dag_format?(source)
    end

    test "returns false for missing steps key" do
      refute Validator.dag_format?(%{"code" => "print('hello')"})
    end
  end

  describe "build_dependency_graph/1" do
    test "builds correct dependency graph" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_a", "step_b"]}
      }

      graph = Validator.build_dependency_graph(steps)

      assert graph["step_a"] == []
      assert graph["step_b"] == ["step_a"]
      assert Enum.sort(graph["step_c"]) == ["step_a", "step_b"]
    end
  end

  describe "build_dependents_graph/1" do
    test "builds correct dependents (reverse) graph" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_a", "step_b"]}
      }

      graph = Validator.build_dependents_graph(steps)

      assert Enum.sort(graph["step_a"]) == ["step_b", "step_c"]
      assert graph["step_b"] == ["step_c"]
      assert graph["step_c"] == []
    end
  end

  describe "find_root_steps/1" do
    test "finds steps with no dependencies" do
      steps = %{
        "init" => %{"type" => "log"},
        "begin" => %{"type" => "log"},
        "process" => %{"type" => "log", "depends_on" => ["init", "begin"]}
      }

      roots = Validator.find_root_steps(steps)
      assert Enum.sort(roots) == ["begin", "init"]
    end
  end

  describe "find_terminal_steps/1" do
    test "finds steps that no other step depends on" do
      steps = %{
        "init" => %{"type" => "log"},
        "process" => %{"type" => "log", "depends_on" => ["init"]},
        "finalize" => %{"type" => "log", "depends_on" => ["process"]}
      }

      terminals = Validator.find_terminal_steps(steps)
      assert terminals == ["finalize"]
    end
  end

  describe "topological_sort/1" do
    test "returns valid ordering for DAG" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      assert {:ok, ordered} = Validator.topological_sort(steps)
      assert ordered == ["step_a", "step_b", "step_c"]
    end

    test "handles parallel branches" do
      steps = %{
        "init" => %{"type" => "log"},
        "branch_a" => %{"type" => "wait", "depends_on" => ["init"]},
        "branch_b" => %{"type" => "wait", "depends_on" => ["init"]},
        "join" => %{"type" => "log", "depends_on" => ["branch_a", "branch_b"]}
      }

      assert {:ok, ordered} = Validator.topological_sort(steps)

      # init must come first
      assert hd(ordered) == "init"
      # join must come last
      assert List.last(ordered) == "join"
      # branches can be in any order between init and join
      assert "branch_a" in ordered
      assert "branch_b" in ordered
    end

    test "returns error for cyclic graph" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_b"]},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      assert {:error, :cycle_detected} = Validator.topological_sort(steps)
    end
  end
end
