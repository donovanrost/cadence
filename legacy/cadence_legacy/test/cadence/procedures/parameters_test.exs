defmodule Cadence.Procedures.ParametersTest do
  use Cadence.PureCase, async: true

  alias Cadence.Procedures.Parameters

  describe "validate/3" do
    setup do
      context = %{mission_id: Ecto.UUID.generate(), organization_id: Ecto.UUID.generate()}
      {:ok, context: context}
    end

    test "returns params unchanged when schema is nil", %{context: context} do
      params = %{"foo" => "bar"}
      assert {:ok, ^params} = Parameters.validate(params, nil, context)
    end

    test "returns params unchanged when schema is empty", %{context: context} do
      params = %{"foo" => "bar"}
      assert {:ok, ^params} = Parameters.validate(params, %{}, context)
    end

    test "returns params unchanged when parameters list is empty", %{context: context} do
      params = %{"foo" => "bar"}
      schema = %{"parameters" => []}
      assert {:ok, ^params} = Parameters.validate(params, schema, context)
    end

    test "validates required string parameter", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "name", "type" => "string", "required" => true}
        ]
      }

      assert {:ok, %{"name" => "test"}} =
               Parameters.validate(%{"name" => "test"}, schema, context)

      assert {:error, [{"name", "is required"}]} = Parameters.validate(%{}, schema, context)
      assert {:error, [{"name", "is required"}]} = Parameters.validate(nil, schema, context)
    end

    test "applies default values", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "threshold", "type" => "number", "default" => 50}
        ]
      }

      assert {:ok, %{"threshold" => 50}} = Parameters.validate(%{}, schema, context)

      assert {:ok, %{"threshold" => 75}} =
               Parameters.validate(%{"threshold" => 75}, schema, context)
    end

    test "validates string min/max length", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "code", "type" => "string", "min_length" => 3, "max_length" => 10}
        ]
      }

      assert {:ok, _} = Parameters.validate(%{"code" => "ABC"}, schema, context)
      assert {:ok, _} = Parameters.validate(%{"code" => "ABCDEFGHIJ"}, schema, context)

      assert {:error, [{"code", "must be at least 3 characters"}]} =
               Parameters.validate(%{"code" => "AB"}, schema, context)

      assert {:error, [{"code", "must be at most 10 characters"}]} =
               Parameters.validate(%{"code" => "ABCDEFGHIJK"}, schema, context)
    end

    test "validates string pattern", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "id", "type" => "string", "pattern" => "^[A-Z]{2}-\\d{3}$"}
        ]
      }

      assert {:ok, _} = Parameters.validate(%{"id" => "SC-001"}, schema, context)

      assert {:error, [{"id", "must match pattern: ^[A-Z]{2}-\\d{3}$"}]} =
               Parameters.validate(%{"id" => "invalid"}, schema, context)
    end

    test "validates number type with min/max", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "temp", "type" => "number", "min" => 0, "max" => 100}
        ]
      }

      assert {:ok, %{"temp" => 50}} = Parameters.validate(%{"temp" => 50}, schema, context)
      assert {:ok, %{"temp" => 50.5}} = Parameters.validate(%{"temp" => 50.5}, schema, context)

      # Parses string to number
      assert {:ok, %{"temp" => 50.0}} = Parameters.validate(%{"temp" => "50"}, schema, context)

      assert {:error, [{"temp", "must be at least 0"}]} =
               Parameters.validate(%{"temp" => -1}, schema, context)

      assert {:error, [{"temp", "must be at most 100"}]} =
               Parameters.validate(%{"temp" => 101}, schema, context)
    end

    test "validates integer type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "count", "type" => "integer", "min" => 1}
        ]
      }

      assert {:ok, %{"count" => 5}} = Parameters.validate(%{"count" => 5}, schema, context)
      assert {:ok, %{"count" => 5}} = Parameters.validate(%{"count" => "5"}, schema, context)

      # Float that's a whole number is ok
      assert {:ok, %{"count" => 5}} = Parameters.validate(%{"count" => 5.0}, schema, context)

      assert {:error, [{"count", "must be an integer"}]} =
               Parameters.validate(%{"count" => 5.5}, schema, context)
    end

    test "validates boolean type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "enabled", "type" => "boolean"}
        ]
      }

      assert {:ok, %{"enabled" => true}} =
               Parameters.validate(%{"enabled" => true}, schema, context)

      assert {:ok, %{"enabled" => false}} =
               Parameters.validate(%{"enabled" => false}, schema, context)

      # String coercion
      assert {:ok, %{"enabled" => true}} =
               Parameters.validate(%{"enabled" => "true"}, schema, context)

      assert {:ok, %{"enabled" => false}} =
               Parameters.validate(%{"enabled" => "false"}, schema, context)

      assert {:error, [{"enabled", "must be a boolean"}]} =
               Parameters.validate(%{"enabled" => "yes"}, schema, context)
    end

    test "validates enum type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "mode", "type" => "enum", "options" => ["nominal", "safe", "emergency"]}
        ]
      }

      assert {:ok, %{"mode" => "nominal"}} =
               Parameters.validate(%{"mode" => "nominal"}, schema, context)

      assert {:ok, %{"mode" => "safe"}} =
               Parameters.validate(%{"mode" => "safe"}, schema, context)

      assert {:error, [{"mode", "must be one of: nominal, safe, emergency"}]} =
               Parameters.validate(%{"mode" => "invalid"}, schema, context)
    end

    test "validates array type", %{context: context} do
      schema = %{
        "parameters" => [
          %{
            "name" => "zones",
            "type" => "array",
            "min_items" => 1,
            "max_items" => 3,
            "items" => %{"type" => "integer"}
          }
        ]
      }

      assert {:ok, %{"zones" => [1, 2]}} =
               Parameters.validate(%{"zones" => [1, 2]}, schema, context)

      assert {:error, [{"zones", "must have at least 1 items"}]} =
               Parameters.validate(%{"zones" => []}, schema, context)

      assert {:error, [{"zones", "must have at most 3 items"}]} =
               Parameters.validate(%{"zones" => [1, 2, 3, 4]}, schema, context)

      assert {:error, [{"zones", "item 1: must be an integer"}]} =
               Parameters.validate(%{"zones" => [1, "two"]}, schema, context)
    end

    test "validates duration type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "timeout", "type" => "duration", "min" => 1000, "max" => 60_000}
        ]
      }

      assert {:ok, %{"timeout" => 5000}} =
               Parameters.validate(%{"timeout" => 5000}, schema, context)

      assert {:error, [{"timeout", "must be at least 1000"}]} =
               Parameters.validate(%{"timeout" => 500}, schema, context)
    end

    test "validates datetime type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "scheduled_at", "type" => "datetime"}
        ]
      }

      assert {:ok, %{"scheduled_at" => %DateTime{}}} =
               Parameters.validate(%{"scheduled_at" => "2024-01-15T10:30:00Z"}, schema, context)

      dt = DateTime.utc_now()

      assert {:ok, %{"scheduled_at" => ^dt}} =
               Parameters.validate(%{"scheduled_at" => dt}, schema, context)

      assert {:error, [{"scheduled_at", "must be a valid ISO8601 datetime"}]} =
               Parameters.validate(%{"scheduled_at" => "invalid"}, schema, context)
    end

    test "validates telemetry_item type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "item", "type" => "telemetry_item"}
        ]
      }

      assert {:ok, _} = Parameters.validate(%{"item" => "POWER.voltage"}, schema, context)

      assert {:error, [{"item", "must be in format PACKET.item"}]} =
               Parameters.validate(%{"item" => "voltage"}, schema, context)
    end

    test "validates command type", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "cmd", "type" => "command"}
        ]
      }

      assert {:ok, _} = Parameters.validate(%{"cmd" => "HEATER_ON"}, schema, context)

      assert {:error, [{"cmd", "command name cannot be empty"}]} =
               Parameters.validate(%{"cmd" => "  "}, schema, context)
    end

    test "collects multiple validation errors", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "a", "type" => "string", "required" => true},
          %{"name" => "b", "type" => "integer", "required" => true}
        ]
      }

      assert {:error, errors} = Parameters.validate(%{}, schema, context)
      assert length(errors) == 2
      assert {"a", "is required"} in errors
      assert {"b", "is required"} in errors
    end

    test "allows nil for optional parameters", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "optional", "type" => "string", "required" => false}
        ]
      }

      assert {:ok, %{"optional" => nil}} = Parameters.validate(%{}, schema, context)
    end

    test "supports atom keys in params", %{context: context} do
      schema = %{
        "parameters" => [
          %{"name" => "name", "type" => "string", "required" => true}
        ]
      }

      # Atom keys are supported for lookup, output uses string keys from schema
      {:ok, result} = Parameters.validate(%{name: "test"}, schema, context)
      assert result["name"] == "test"
    end
  end

  describe "validate_schema/1" do
    test "returns :ok for valid schema" do
      schema = %{
        "parameters" => [
          %{"name" => "target_id", "type" => "string", "required" => true},
          %{"name" => "threshold", "type" => "number", "default" => 50}
        ]
      }

      assert :ok = Parameters.validate_schema(schema)
    end

    test "returns :ok for nil or empty schema" do
      assert :ok = Parameters.validate_schema(nil)
      assert :ok = Parameters.validate_schema(%{})
    end

    test "returns error for missing name" do
      schema = %{
        "parameters" => [
          %{"type" => "string"}
        ]
      }

      assert {:error, msg} = Parameters.validate_schema(schema)
      assert msg =~ "must have a 'name' string"
    end

    test "returns error for invalid type" do
      schema = %{
        "parameters" => [
          %{"name" => "foo", "type" => "invalid"}
        ]
      }

      assert {:error, msg} = Parameters.validate_schema(schema)
      assert msg =~ "must have a valid 'type'"
    end

    test "returns error for enum without options" do
      schema = %{
        "parameters" => [
          %{"name" => "mode", "type" => "enum"}
        ]
      }

      assert {:error, msg} = Parameters.validate_schema(schema)
      assert msg =~ "enum type requires 'options' list"
    end
  end

  describe "defaults/1" do
    test "returns defaults from schema" do
      schema = %{
        "parameters" => [
          %{"name" => "a", "type" => "string", "default" => "hello"},
          %{"name" => "b", "type" => "number", "default" => 42},
          %{"name" => "c", "type" => "string"}
        ]
      }

      assert %{"a" => "hello", "b" => 42} = Parameters.defaults(schema)
    end

    test "returns empty map for nil schema" do
      assert %{} = Parameters.defaults(nil)
    end
  end

  describe "required_params/1" do
    test "returns required parameter names" do
      schema = %{
        "parameters" => [
          %{"name" => "a", "type" => "string", "required" => true},
          %{"name" => "b", "type" => "number", "required" => false},
          %{"name" => "c", "type" => "string", "required" => true}
        ]
      }

      required = Parameters.required_params(schema)
      assert "a" in required
      assert "c" in required
      refute "b" in required
    end

    test "returns empty list for nil schema" do
      assert [] = Parameters.required_params(nil)
    end
  end

  describe "supported_types/0" do
    test "returns all supported types" do
      types = Parameters.supported_types()

      assert "string" in types
      assert "number" in types
      assert "integer" in types
      assert "boolean" in types
      assert "enum" in types
      assert "array" in types
      assert "target" in types
      assert "telemetry_item" in types
      assert "command" in types
      assert "duration" in types
      assert "datetime" in types
    end
  end
end
