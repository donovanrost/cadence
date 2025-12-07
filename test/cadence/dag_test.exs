defmodule Cadence.DagTest do
  use ExUnit.Case, async: true

  alias Cadence.Dag

  @moduledoc """
  Tests for the public Dag facade module.
  """

  defp simple_executor do
    fn step_name, _step_def, _context ->
      {:ok, %{step: step_name}}
    end
  end

  describe "execute/4" do
    test "executes a simple DAG" do
      steps = %{
        "step_a" => %{"type" => "log", "message" => "Hello", "depends_on" => []},
        "step_b" => %{"type" => "log", "message" => "World", "depends_on" => ["step_a"]}
      }

      {:ok, result} = Dag.execute(steps, simple_executor(), %{})

      assert result.status == :completed
      assert "step_a" in result.completed_steps
      assert "step_b" in result.completed_steps
    end

    test "supports max_concurrency option" do
      steps = %{
        "parallel_1" => %{"type" => "wait", "duration" => 100},
        "parallel_2" => %{"type" => "wait", "duration" => 100}
      }

      {:ok, result} = Dag.execute(steps, simple_executor(), %{}, max_concurrency: 1)

      assert result.status == :completed
      assert length(result.completed_steps) == 2
    end

    test "supports on_step_failure option" do
      steps = %{
        "failing_step" => %{"type" => "fail"},
        "dependent" => %{"type" => "log", "depends_on" => ["failing_step"]}
      }

      failing_executor = fn step_name, _step_def, _context ->
        if step_name == "failing_step" do
          {:error, "intentional failure"}
        else
          {:ok, %{step: step_name}}
        end
      end

      {:ok, result} = Dag.execute(steps, failing_executor, %{}, on_step_failure: :continue)

      assert result.status == :completed_with_failures
      assert "failing_step" in result.failed_steps
      assert "dependent" in result.blocked_steps
    end
  end

  describe "validate/1" do
    test "returns :ok for valid DAG" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      assert :ok = Dag.validate(steps)
    end

    test "returns error for cyclic DAG" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_b"]},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      {:error, reasons} = Dag.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "Cycle"))
    end

    test "returns error for missing dependencies" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["nonexistent"]}
      }

      {:error, reasons} = Dag.validate(steps)
      assert Enum.any?(reasons, &String.contains?(&1, "non-existent"))
    end
  end

  describe "dag_format?/1" do
    test "returns true for map-based steps" do
      source = %{"steps" => %{"step_a" => %{"type" => "log"}}}
      assert Dag.dag_format?(source)
    end

    test "returns false for list-based steps" do
      source = %{"steps" => [%{"type" => "log"}]}
      refute Dag.dag_format?(source)
    end

    test "returns false for non-map input" do
      refute Dag.dag_format?(%{"code" => "print('hello')"})
    end
  end

  describe "dependency_graph/1" do
    test "builds correct dependency graph" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_a", "step_b"]}
      }

      graph = Dag.dependency_graph(steps)

      assert graph["step_a"] == []
      assert graph["step_b"] == ["step_a"]
      assert "step_a" in graph["step_c"]
      assert "step_b" in graph["step_c"]
    end
  end

  describe "dependents_graph/1" do
    test "builds correct reverse dependency graph" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      graph = Dag.dependents_graph(steps)

      assert "step_b" in graph["step_a"]
      assert "step_c" in graph["step_b"]
      assert graph["step_c"] == []
    end
  end
end
