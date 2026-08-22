defmodule Cadence.Procedures.InputReferencesTest do
  use ExUnit.Case, async: true

  alias Cadence.Procedures.InputReferences

  describe "extract_references/1" do
    test "extracts single reference" do
      assert InputReferences.extract_references("Value is ${input.threshold}") == ["threshold"]
    end

    test "extracts multiple references" do
      refs = InputReferences.extract_references("${input.a} and ${input.b} and ${input.a}")
      assert Enum.sort(refs) == ["a", "b"]
    end

    test "returns empty list for no references" do
      assert InputReferences.extract_references("no references here") == []
    end

    test "handles nil and non-strings" do
      assert InputReferences.extract_references(nil) == []
      assert InputReferences.extract_references(123) == []
    end
  end

  describe "extract_references_from_step/1" do
    test "extracts from nested step config" do
      step = %{
        "type" => "command",
        "name" => "${input.command_name}",
        "args" => %{
          "zone" => "${input.zone}",
          "value" => 123
        }
      }

      refs = InputReferences.extract_references_from_step(step)
      assert Enum.sort(refs) == ["command_name", "zone"]
    end

    test "extracts from lists" do
      step = %{
        "type" => "log",
        "messages" => ["${input.a}", "${input.b}"]
      }

      refs = InputReferences.extract_references_from_step(step)
      assert Enum.sort(refs) == ["a", "b"]
    end
  end

  describe "validate_references/2" do
    test "returns :ok when all references are defined" do
      steps = %{
        "step1" => %{"type" => "wait", "duration" => "${input.wait_time}"}
      }

      inputs = %{"wait_time" => %{"type" => "duration"}}

      assert InputReferences.validate_references(steps, inputs) == :ok
    end

    test "returns error for undefined references" do
      steps = %{
        "step1" => %{"type" => "command", "name" => "${input.undefined}"}
      }

      inputs = %{}

      assert {:error, errors} = InputReferences.validate_references(steps, inputs)
      assert {"step1", "undefined"} in errors
    end

    test "returns multiple errors" do
      steps = %{
        "step1" => %{"message" => "${input.a}"},
        "step2" => %{"value" => "${input.b}"}
      }

      inputs = %{}

      assert {:error, errors} = InputReferences.validate_references(steps, inputs)
      assert length(errors) == 2
    end
  end

  describe "interpolate/2" do
    test "replaces input references with values" do
      assert {:ok, "Value is 42"} =
               InputReferences.interpolate("Value is ${input.threshold}", %{"threshold" => 42})
    end

    test "handles multiple references" do
      result =
        InputReferences.interpolate(
          "${input.a} + ${input.b} = ${input.c}",
          %{"a" => 1, "b" => 2, "c" => 3}
        )

      assert {:ok, "1 + 2 = 3"} = result
    end

    test "returns error for missing input" do
      assert {:error, :missing_input, "undefined"} =
               InputReferences.interpolate("${input.undefined}", %{})
    end

    test "handles non-string values" do
      assert {:ok, 123} = InputReferences.interpolate(123, %{})
    end
  end

  describe "interpolate_step/2" do
    test "interpolates all values in step" do
      step = %{
        "type" => "command",
        "name" => "${input.cmd}",
        "args" => %{"zone" => "${input.zone}"}
      }

      inputs = %{"cmd" => "POWER_ON", "zone" => "PRIMARY"}

      assert {:ok, result} = InputReferences.interpolate_step(step, inputs)
      assert result["name"] == "POWER_ON"
      assert result["args"]["zone"] == "PRIMARY"
    end

    test "returns error if any reference is missing" do
      step = %{"name" => "${input.missing}"}

      assert {:error, :missing_input, "missing"} =
               InputReferences.interpolate_step(step, %{})
    end
  end

  describe "has_references?/1" do
    test "returns true for strings with references" do
      assert InputReferences.has_references?("${input.foo}")
      assert InputReferences.has_references?("prefix ${input.foo} suffix")
    end

    test "returns false for strings without references" do
      refute InputReferences.has_references?("no references")
      refute InputReferences.has_references?("")
    end

    test "returns false for non-strings" do
      refute InputReferences.has_references?(nil)
      refute InputReferences.has_references?(123)
    end
  end
end
