defmodule Cadence.Procedures.Dag.StepExecutorTest do
  use ExUnit.Case, async: true

  alias Cadence.Procedures.Dag.StepExecutor

  describe "create_executor/1" do
    test "returns a function" do
      executor = StepExecutor.create_executor()
      assert is_function(executor, 3)
    end
  end

  describe "execute_step/4 check type" do
    test "check with condition true returns ok" do
      step = %{"type" => "check", "condition" => "true"}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("my_check", step, context)
      assert result.condition == "true"
      assert result.result == true
    end

    test "check with condition false and abort returns error" do
      step = %{
        "type" => "check",
        "condition" => "false",
        "message" => "Check failed!"
      }

      context = %{}

      assert {:error, "Check failed!"} = StepExecutor.execute_step("my_check", step, context)
    end

    test "check with condition false and skip returns skip" do
      step = %{
        "type" => "check",
        "condition" => "false",
        "on_fail" => "skip",
        "message" => "Skipping"
      }

      context = %{}

      assert {:skip, "Skipping"} = StepExecutor.execute_step("my_check", step, context)
    end

    test "check with condition false and warn returns ok with warning" do
      step = %{
        "type" => "check",
        "condition" => "false",
        "on_fail" => "warn",
        "message" => "Warning message"
      }

      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("my_check", step, context)
      assert result.warning == "Warning message"
      assert result.result == false
    end
  end

  describe "execute_step/4 wait type" do
    test "wait sleeps for specified duration" do
      step = %{"type" => "wait", "duration" => 10}
      context = %{}

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = StepExecutor.execute_step("my_wait", step, context)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert result.waited == 10
      assert elapsed >= 10
    end

    test "wait defaults to 0ms duration" do
      step = %{"type" => "wait"}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("my_wait", step, context)
      assert result.waited == 0
    end
  end

  describe "execute_step/4 log type" do
    test "log with info level succeeds" do
      step = %{"type" => "log", "level" => "info", "message" => "Test message"}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("my_log", step, context)
      assert result.level == :info
      assert result.message == "Test message"
    end

    test "log defaults to info level" do
      step = %{"type" => "log", "message" => "Test message"}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("my_log", step, context)
      assert result.level == :info
    end

    test "log resolves template variables" do
      step = %{"type" => "log", "message" => "Value is {{params.foo}}"}
      context = %{params: %{"foo" => "bar"}}

      assert {:ok, result} = StepExecutor.execute_step("my_log", step, context)
      assert result.message == "Value is bar"
    end
  end

  describe "execute_step/4 set type" do
    test "set stores variable with step prefix" do
      step = %{"type" => "set", "name" => "result", "value" => 42}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("calc", step, context)
      assert result.variable == "calc.result"
      assert result.value == 42
      assert result.set_var == {"calc.result", 42}
    end

    test "set resolves params reference" do
      step = %{"type" => "set", "name" => "target", "value" => "params.target_id"}
      context = %{params: %{"target_id" => "sat-01"}}

      assert {:ok, result} = StepExecutor.execute_step("init", step, context)
      assert result.value == "sat-01"
    end
  end

  describe "execute_step/4 assert type" do
    test "assert with true condition succeeds" do
      step = %{"type" => "assert", "condition" => "true"}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("my_assert", step, context)
      assert result.result == true
    end

    test "assert with false condition fails" do
      step = %{
        "type" => "assert",
        "condition" => "false",
        "message" => "Assertion failed!"
      }

      context = %{}

      assert {:error, "Assertion failed!"} = StepExecutor.execute_step("my_assert", step, context)
    end
  end

  describe "execute_step/4 unknown type" do
    test "unknown step type returns error" do
      step = %{"type" => "unknown_type"}
      context = %{}

      assert {:error, "Unknown step type: unknown_type"} =
               StepExecutor.execute_step("bad_step", step, context)
    end
  end

  describe "execute_step/4 invalid step" do
    test "step without type map returns error" do
      step = %{"message" => "Hello"}
      context = %{}

      assert {:error, "Invalid step definition"} =
               StepExecutor.execute_step("bad_step", step, context)
    end

    test "non-map step returns error" do
      step = "not a map"
      context = %{}

      assert {:error, "Invalid step definition"} =
               StepExecutor.execute_step("bad_step", step, context)
    end
  end

  describe "value resolution" do
    test "resolves params.* references" do
      step = %{"type" => "log", "message" => "params.name"}
      context = %{params: %{"name" => "test-value"}}

      # The log message itself isn't resolved directly by log,
      # but we can test via set which does resolve values
      set_step = %{"type" => "set", "name" => "x", "value" => "params.name"}

      assert {:ok, result} = StepExecutor.execute_step("test", set_step, context)
      assert result.value == "test-value"
    end

    test "resolves trigger.* references" do
      step = %{"type" => "set", "name" => "alarm", "value" => "trigger.source_name"}
      context = %{trigger: %{"source_name" => "BATTERY_LOW"}}

      assert {:ok, result} = StepExecutor.execute_step("test", step, context)
      assert result.value == "BATTERY_LOW"
    end

    test "resolves trigger.data.* nested references" do
      step = %{"type" => "set", "name" => "sev", "value" => "trigger.data.severity"}
      context = %{trigger: %{"data" => %{"severity" => "warning"}}}

      assert {:ok, result} = StepExecutor.execute_step("test", step, context)
      assert result.value == "warning"
    end

    test "resolves vars.* references" do
      step = %{"type" => "set", "name" => "copy", "value" => "vars.prev_result"}
      context = %{vars: %{"prev_result" => 123}}

      assert {:ok, result} = StepExecutor.execute_step("test", step, context)
      assert result.value == 123
    end

    test "resolves template {{}} syntax" do
      step = %{"type" => "log", "message" => "Hello {{params.name}}, status: {{params.status}}"}
      context = %{params: %{"name" => "World", "status" => "OK"}}

      assert {:ok, result} = StepExecutor.execute_step("test", step, context)
      assert result.message == "Hello World, status: OK"
    end

    test "plain strings are returned as-is" do
      step = %{"type" => "set", "name" => "x", "value" => "plain string"}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("test", step, context)
      assert result.value == "plain string"
    end

    test "non-string values are returned as-is" do
      step = %{"type" => "set", "name" => "x", "value" => 42}
      context = %{}

      assert {:ok, result} = StepExecutor.execute_step("test", step, context)
      assert result.value == 42
    end
  end
end
