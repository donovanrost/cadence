defmodule Cadence.Procedures.Parameters do
  @moduledoc """
  Parameter schema definition and validation for procedures.

  Procedures can define expected input parameters using a schema. Parameters
  are validated at execution time before the procedure runs.

  ## Schema Format

  The `parameters_schema` is a map with a "parameters" key containing a list
  of parameter definitions:

      %{
        "parameters" => [
          %{
            "name" => "target_id",
            "type" => "target",
            "required" => true,
            "description" => "Target spacecraft"
          },
          %{
            "name" => "threshold",
            "type" => "number",
            "required" => false,
            "default" => 50,
            "min" => 0,
            "max" => 100
          }
        ]
      }

  ## Supported Types

  - `string` - Text value, with optional `min_length`, `max_length`, `pattern`
  - `number` - Numeric value (float), with optional `min`, `max`
  - `integer` - Integer value, with optional `min`, `max`
  - `boolean` - True/false
  - `enum` - One of a set of `options`
  - `array` - List of values, with `items` schema
  - `target` - Valid target ID for the mission
  - `telemetry_item` - Valid telemetry item path
  - `command` - Valid command name
  - `duration` - Duration in milliseconds
  - `datetime` - UTC datetime

  ## Validation

  Use `validate/3` to validate parameters against a schema:

      case Parameters.validate(params, schema, context) do
        {:ok, validated_params} -> # proceed
        {:error, errors} -> # handle validation errors
      end
  """

  alias Cadence.Targets

  @type param_type ::
          :string
          | :number
          | :integer
          | :boolean
          | :enum
          | :array
          | :target
          | :telemetry_item
          | :command
          | :duration
          | :datetime

  @type param_def :: %{
          required(:name) => String.t(),
          required(:type) => param_type(),
          optional(:required) => boolean(),
          optional(:default) => any(),
          optional(:description) => String.t(),
          optional(:min) => number(),
          optional(:max) => number(),
          optional(:min_length) => non_neg_integer(),
          optional(:max_length) => non_neg_integer(),
          optional(:pattern) => String.t(),
          optional(:options) => list(String.t()),
          optional(:items) => map()
        }

  @type validation_context :: %{
          required(:mission_id) => String.t(),
          optional(:organization_id) => String.t()
        }

  @type validation_error :: {String.t(), String.t()}

  @supported_types ~w(string number integer boolean enum array target telemetry_item command duration datetime)

  @doc """
  Validates parameters against a schema.

  Returns `{:ok, validated_params}` with defaults applied, or
  `{:error, errors}` with a list of `{param_name, message}` tuples.
  """
  @spec validate(map(), map() | nil, validation_context()) ::
          {:ok, map()} | {:error, list(validation_error())}
  def validate(params, nil, _context), do: {:ok, params || %{}}

  def validate(params, %{"parameters" => param_defs}, context) when is_list(param_defs) and param_defs != [] do
    params = params || %{}

    {validated, errors} =
      Enum.reduce(param_defs, {%{}, []}, fn param_def, {acc_validated, acc_errors} ->
        name = param_def["name"]
        value = get_param_value(params, name, param_def["default"])

        case validate_param(value, param_def, context) do
          {:ok, validated_value} ->
            {Map.put(acc_validated, name, validated_value), acc_errors}

          {:error, error} ->
            {acc_validated, [{name, error} | acc_errors]}
        end
      end)

    case errors do
      [] -> {:ok, validated}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Empty or missing parameters list - pass through
  def validate(params, _schema, _context), do: {:ok, params || %{}}

  @doc """
  Validates a parameter schema definition itself.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate_schema(map()) :: :ok | {:error, String.t()}
  def validate_schema(nil), do: :ok

  def validate_schema(%{"parameters" => params}) when is_list(params) and params != [] do
    errors =
      params
      |> Enum.with_index()
      |> Enum.flat_map(fn {param, index} ->
        validate_param_def(param, index)
      end)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.join(errors, "; ")}
    end
  end

  # Empty schema or empty parameters list is valid
  def validate_schema(%{"parameters" => []}), do: :ok
  def validate_schema(%{}), do: :ok
  def validate_schema(_), do: {:error, "Schema must have a 'parameters' list"}

  # ============================================================================
  # Parameter Validation
  # ============================================================================

  defp get_param_value(params, name, default) do
    # Support both string and atom keys
    case Map.get(params, name) do
      nil -> Map.get(params, String.to_existing_atom(name), default)
      value -> value
    end
  rescue
    ArgumentError -> default
  end

  defp validate_param(nil, %{"required" => true}, _context) do
    {:error, "is required"}
  end

  defp validate_param(nil, _param_def, _context) do
    {:ok, nil}
  end

  defp validate_param(value, %{"type" => "string"} = param_def, _context) do
    with :ok <- validate_is_string(value),
         :ok <- validate_min_length(value, param_def["min_length"]),
         :ok <- validate_max_length(value, param_def["max_length"]),
         :ok <- validate_pattern(value, param_def["pattern"]) do
      {:ok, value}
    end
  end

  defp validate_param(value, %{"type" => "number"} = param_def, _context) do
    with {:ok, num} <- validate_is_number(value),
         :ok <- validate_min(num, param_def["min"]),
         :ok <- validate_max(num, param_def["max"]) do
      {:ok, num}
    end
  end

  defp validate_param(value, %{"type" => "integer"} = param_def, _context) do
    with {:ok, int} <- validate_is_integer(value),
         :ok <- validate_min(int, param_def["min"]),
         :ok <- validate_max(int, param_def["max"]) do
      {:ok, int}
    end
  end

  defp validate_param(value, %{"type" => "boolean"}, _context) do
    validate_is_boolean(value)
  end

  defp validate_param(value, %{"type" => "enum", "options" => options}, _context)
       when is_list(options) do
    if value in options do
      {:ok, value}
    else
      {:error, "must be one of: #{Enum.join(options, ", ")}"}
    end
  end

  defp validate_param(_value, %{"type" => "enum"}, _context) do
    {:error, "enum type requires 'options' list"}
  end

  defp validate_param(value, %{"type" => "array"} = param_def, context) do
    with :ok <- validate_is_list(value),
         :ok <- validate_min_items(value, param_def["min_items"]),
         :ok <- validate_max_items(value, param_def["max_items"]),
         {:ok, validated_items} <- validate_array_items(value, param_def["items"], context) do
      {:ok, validated_items}
    end
  end

  defp validate_param(value, %{"type" => "target"}, context) do
    with :ok <- validate_is_string(value) do
      if target_exists?(context.mission_id, value) do
        {:ok, value}
      else
        {:error, "is not a valid target for this mission"}
      end
    end
  end

  defp validate_param(value, %{"type" => "telemetry_item"}, _context) do
    # For now, just validate it's a string in the format PACKET.item
    with :ok <- validate_is_string(value) do
      if String.contains?(value, ".") do
        {:ok, value}
      else
        {:error, "must be in format PACKET.item"}
      end
    end
  end

  defp validate_param(value, %{"type" => "command"}, _context) do
    # For now, just validate it's a non-empty string
    with :ok <- validate_is_string(value) do
      if String.trim(value) != "" do
        {:ok, value}
      else
        {:error, "command name cannot be empty"}
      end
    end
  end

  defp validate_param(value, %{"type" => "duration"} = param_def, _context) do
    with {:ok, ms} <- validate_is_integer(value),
         :ok <- validate_min(ms, param_def["min"] || 0),
         :ok <- validate_max(ms, param_def["max"]) do
      {:ok, ms}
    end
  end

  defp validate_param(value, %{"type" => "datetime"}, _context) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, "must be a valid ISO8601 datetime"}
    end
  end

  defp validate_param(%DateTime{} = value, %{"type" => "datetime"}, _context) do
    {:ok, value}
  end

  defp validate_param(_value, %{"type" => "datetime"}, _context) do
    {:error, "must be a datetime"}
  end

  defp validate_param(_value, %{"type" => type}, _context) do
    {:error, "unsupported parameter type: #{type}"}
  end

  # ============================================================================
  # Type Validators
  # ============================================================================

  defp validate_is_string(value) when is_binary(value), do: :ok
  defp validate_is_string(_), do: {:error, "must be a string"}

  defp validate_is_number(value) when is_number(value), do: {:ok, value}

  defp validate_is_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> {:ok, num}
      _ -> {:error, "must be a number"}
    end
  end

  defp validate_is_number(_), do: {:error, "must be a number"}

  defp validate_is_integer(value) when is_integer(value), do: {:ok, value}

  defp validate_is_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "must be an integer"}
    end
  end

  defp validate_is_integer(value) when is_float(value) do
    if value == trunc(value) do
      {:ok, trunc(value)}
    else
      {:error, "must be an integer"}
    end
  end

  defp validate_is_integer(_), do: {:error, "must be an integer"}

  defp validate_is_boolean(true), do: {:ok, true}
  defp validate_is_boolean(false), do: {:ok, false}
  defp validate_is_boolean("true"), do: {:ok, true}
  defp validate_is_boolean("false"), do: {:ok, false}
  defp validate_is_boolean(_), do: {:error, "must be a boolean"}

  defp validate_is_list(value) when is_list(value), do: :ok
  defp validate_is_list(_), do: {:error, "must be an array"}

  # ============================================================================
  # Constraint Validators
  # ============================================================================

  defp validate_min(_value, nil), do: :ok
  defp validate_min(value, min) when value >= min, do: :ok
  defp validate_min(_value, min), do: {:error, "must be at least #{min}"}

  defp validate_max(_value, nil), do: :ok
  defp validate_max(value, max) when value <= max, do: :ok
  defp validate_max(_value, max), do: {:error, "must be at most #{max}"}

  defp validate_min_length(_value, nil), do: :ok
  defp validate_min_length(value, min) when byte_size(value) >= min, do: :ok
  defp validate_min_length(_value, min), do: {:error, "must be at least #{min} characters"}

  defp validate_max_length(_value, nil), do: :ok
  defp validate_max_length(value, max) when byte_size(value) <= max, do: :ok
  defp validate_max_length(_value, max), do: {:error, "must be at most #{max} characters"}

  defp validate_pattern(_value, nil), do: :ok

  defp validate_pattern(value, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        if Regex.match?(regex, value) do
          :ok
        else
          {:error, "must match pattern: #{pattern}"}
        end

      {:error, _} ->
        {:error, "invalid pattern in schema: #{pattern}"}
    end
  end

  defp validate_min_items(_value, nil), do: :ok
  defp validate_min_items(value, min) when length(value) >= min, do: :ok
  defp validate_min_items(_value, min), do: {:error, "must have at least #{min} items"}

  defp validate_max_items(_value, nil), do: :ok
  defp validate_max_items(value, max) when length(value) <= max, do: :ok
  defp validate_max_items(_value, max), do: {:error, "must have at most #{max} items"}

  defp validate_array_items(items, nil, _context), do: {:ok, items}
  defp validate_array_items(items, schema, _context) when schema == %{}, do: {:ok, items}

  defp validate_array_items(items, item_schema, context) do
    results =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        case validate_param(item, item_schema, context) do
          {:ok, validated} -> {:ok, validated}
          {:error, msg} -> {:error, "item #{index}: #{msg}"}
        end
      end)

    errors = for {:error, msg} <- results, do: msg
    validated = for {:ok, val} <- results, do: val

    case errors do
      [] -> {:ok, validated}
      errors -> {:error, Enum.join(errors, "; ")}
    end
  end

  # ============================================================================
  # Schema Validation
  # ============================================================================

  defp validate_param_def(param, index) do
    errors = []

    errors =
      if is_map(param) do
        errors
      else
        ["Parameter #{index}: must be a map" | errors]
      end

    errors =
      if is_map(param) and Map.has_key?(param, "name") and is_binary(param["name"]) do
        errors
      else
        ["Parameter #{index}: must have a 'name' string" | errors]
      end

    errors =
      if is_map(param) and Map.has_key?(param, "type") and param["type"] in @supported_types do
        errors
      else
        ["Parameter #{index}: must have a valid 'type' (#{Enum.join(@supported_types, ", ")})" | errors]
      end

    errors =
      if is_map(param) and param["type"] == "enum" and
           (not Map.has_key?(param, "options") or not is_list(param["options"])) do
        ["Parameter #{index}: enum type requires 'options' list" | errors]
      else
        errors
      end

    errors
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp target_exists?(mission_id, target_id) do
    target = Targets.get_target!(target_id)
    target.mission_id == mission_id
  rescue
    Ecto.NoResultsError -> false
  end

  @doc """
  Returns the list of supported parameter types.
  """
  @spec supported_types() :: list(String.t())
  def supported_types, do: @supported_types

  @doc """
  Builds a default value map from a parameter schema.

  Useful for initializing forms.
  """
  @spec defaults(map() | nil) :: map()
  def defaults(nil), do: %{}

  def defaults(%{"parameters" => params}) when is_list(params) do
    params
    |> Enum.filter(&Map.has_key?(&1, "default"))
    |> Enum.map(fn p -> {p["name"], p["default"]} end)
    |> Map.new()
  end

  def defaults(_), do: %{}

  @doc """
  Returns required parameter names from a schema.
  """
  @spec required_params(map() | nil) :: list(String.t())
  def required_params(nil), do: []

  def required_params(%{"parameters" => params}) when is_list(params) do
    params
    |> Enum.filter(&(&1["required"] == true))
    |> Enum.map(& &1["name"])
  end

  def required_params(_), do: []
end
