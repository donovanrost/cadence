defmodule Cadence.Procedures.ConditionEvaluator do
  @moduledoc """
  Unified condition evaluation for procedures.

  Evaluates condition expressions used in DAG steps (check, assert, branch conditions).

  ## Supported Syntax

  - Boolean literals: `"true"`, `"false"`
  - Telemetry comparisons: `"telemetry.PACKET.item >= 50"`
  - Parameter references: `"params.threshold > 0"`
  - Variable references: `"vars.step_name.result == true"`

  ## Important

  Invalid or unparseable conditions return an error, not a default value.
  This is a deliberate design choice to fail fast on typos or malformed conditions.

  ## Examples

      iex> ConditionEvaluator.evaluate("true", %{})
      {:ok, true}

      iex> ConditionEvaluator.evaluate("telemetry.HK.battery_voltage >= 24", context)
      {:ok, true}

      iex> ConditionEvaluator.evaluate("unknown_syntax", %{})
      {:error, {:unknown_condition_format, "unknown_syntax"}}
  """

  require Logger

  alias Cadence.Telemetry.CurrentValueTable, as: CVT

  @type context :: %{
          optional(:mission_id) => String.t(),
          optional(:target_id) => String.t(),
          optional(:params) => map(),
          optional(:vars) => map()
        }

  @type result :: {:ok, boolean()} | {:error, term()}

  @comparison_operators ~w(>= <= > < == !=)

  @doc """
  Evaluates a condition string in the given context.

  Returns `{:ok, boolean}` on success, `{:error, reason}` on failure.

  ## Arguments

  - `condition` - The condition string to evaluate
  - `context` - Map containing mission_id, target_id, params, vars, etc.
  """
  @spec evaluate(term(), context()) :: result()
  def evaluate("true", _context), do: {:ok, true}
  def evaluate("false", _context), do: {:ok, false}
  def evaluate(true, _context), do: {:ok, true}
  def evaluate(false, _context), do: {:ok, false}
  def evaluate(nil, _context), do: {:ok, true}
  def evaluate("", _context), do: {:ok, true}

  def evaluate(condition, context) when is_binary(condition) do
    condition = String.trim(condition)

    cond do
      condition == "true" ->
        {:ok, true}

      condition == "false" ->
        {:ok, false}

      String.starts_with?(condition, "telemetry.") ->
        evaluate_telemetry_condition(condition, context)

      String.starts_with?(condition, "params.") ->
        evaluate_params_condition(condition, context)

      String.starts_with?(condition, "vars.") ->
        evaluate_vars_condition(condition, context)

      # Check if it's a simple comparison without prefix
      has_comparison_operator?(condition) ->
        evaluate_generic_comparison(condition, context)

      true ->
        # Unknown condition format - fail explicitly rather than default to true
        {:error, {:unknown_condition_format, condition}}
    end
  end

  def evaluate(condition, _context) do
    {:error, {:invalid_condition_type, condition}}
  end

  # ============================================================================
  # Telemetry Conditions
  # ============================================================================

  defp evaluate_telemetry_condition(condition, context) do
    # Parse: "telemetry.PACKET.item >= 24" or "telemetry.TARGET.PACKET.item >= 24"
    case parse_comparison(condition, "telemetry.") do
      {:ok, item_path, operator, expected_str} ->
        expected = parse_value(expected_str)

        case get_telemetry_value(item_path, context) do
          {:ok, actual} ->
            {:ok, compare_values(actual, operator, expected)}

          {:error, reason} ->
            {:error, {:telemetry_lookup_failed, item_path, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_telemetry_value(item_path, context) do
    mission_id = context[:mission_id]
    target_id = context[:target_id]

    # Item path format: "PACKET.item" or "TARGET.PACKET.item"
    parts = String.split(item_path, ".")

    {effective_target, packet_name, item_name} =
      case parts do
        [target, packet, item] -> {target, packet, item}
        [packet, item] -> {target_id, packet, item}
        _ -> {nil, nil, nil}
      end

    if packet_name && item_name do
      case CVT.get(mission_id, effective_target, packet_name, item_name) do
        {:ok, %{value: value}} -> {:ok, value}
        {:ok, value} when not is_map(value) -> {:ok, value}
        {:error, :not_found} -> {:error, :not_found}
        _ -> {:error, :cvt_error}
      end
    else
      {:error, :invalid_item_format}
    end
  rescue
    _ -> {:error, :cvt_error}
  end

  # ============================================================================
  # Parameter Conditions
  # ============================================================================

  defp evaluate_params_condition(condition, context) do
    case parse_comparison(condition, "params.") do
      {:ok, param_path, operator, expected_str} ->
        expected = parse_value(expected_str)
        params = context[:params] || %{}

        actual = get_nested_value(params, String.split(param_path, "."))

        if is_nil(actual) do
          {:error, {:param_not_found, param_path}}
        else
          {:ok, compare_values(actual, operator, expected)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Variable Conditions
  # ============================================================================

  defp evaluate_vars_condition(condition, context) do
    case parse_comparison(condition, "vars.") do
      {:ok, var_path, operator, expected_str} ->
        expected = parse_value(expected_str)
        vars = context[:vars] || %{}

        actual = get_nested_value(vars, String.split(var_path, "."))

        if is_nil(actual) do
          # Variables may not exist yet - treat as false rather than error
          {:ok, false}
        else
          {:ok, compare_values(actual, operator, expected)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Generic Comparison (no prefix)
  # ============================================================================

  defp evaluate_generic_comparison(condition, context) do
    # Try to parse as a simple comparison like "value >= 10"
    case parse_generic_comparison(condition) do
      {:ok, left, operator, right} ->
        left_val = resolve_value(left, context)
        right_val = parse_value(right)

        if is_nil(left_val) do
          {:error, {:could_not_resolve, left}}
        else
          {:ok, compare_values(left_val, operator, right_val)}
        end

      {:error, _} ->
        {:error, {:unknown_condition_format, condition}}
    end
  end

  defp resolve_value(value, context) do
    cond do
      String.starts_with?(value, "telemetry.") ->
        path = String.replace_prefix(value, "telemetry.", "")

        case get_telemetry_value(path, context) do
          {:ok, v} -> v
          _ -> nil
        end

      String.starts_with?(value, "params.") ->
        path = String.replace_prefix(value, "params.", "")
        get_nested_value(context[:params] || %{}, String.split(path, "."))

      String.starts_with?(value, "vars.") ->
        path = String.replace_prefix(value, "vars.", "")
        get_nested_value(context[:vars] || %{}, String.split(path, "."))

      true ->
        parse_value(value)
    end
  end

  # ============================================================================
  # Parsing Helpers
  # ============================================================================

  defp parse_comparison(condition, prefix) do
    # Remove prefix and find operator
    rest = String.replace_prefix(condition, prefix, "")

    case find_operator(rest) do
      {left, operator, right} ->
        {:ok, String.trim(left), operator, String.trim(right)}

      nil ->
        {:error, {:no_operator_found, condition}}
    end
  end

  defp parse_generic_comparison(condition) do
    case find_operator(condition) do
      {left, operator, right} ->
        {:ok, String.trim(left), operator, String.trim(right)}

      nil ->
        {:error, :no_operator}
    end
  end

  defp find_operator(str) do
    # Try operators in order of length (longest first to avoid partial matches)
    operators = [">=", "<=", "!=", "==", ">", "<"]

    Enum.find_value(operators, fn op ->
      case String.split(str, op, parts: 2) do
        [left, right] when left != "" and right != "" ->
          {left, op, right}

        _ ->
          nil
      end
    end)
  end

  defp has_comparison_operator?(str) do
    Enum.any?(@comparison_operators, &String.contains?(str, &1))
  end

  defp parse_value(str) when is_binary(str) do
    str = String.trim(str)

    cond do
      str == "true" ->
        true

      str == "false" ->
        false

      str == "nil" ->
        nil

      String.starts_with?(str, "\"") and String.ends_with?(str, "\"") ->
        String.slice(str, 1..-2//1)

      String.starts_with?(str, "'") and String.ends_with?(str, "'") ->
        String.slice(str, 1..-2//1)

      String.match?(str, ~r/^-?\d+$/) ->
        String.to_integer(str)

      String.match?(str, ~r/^-?\d+\.\d+$/) ->
        String.to_float(str)

      true ->
        str
    end
  end

  defp parse_value(value), do: value

  defp get_nested_value(value, []), do: value
  defp get_nested_value(nil, _), do: nil

  defp get_nested_value(map, [key | rest]) when is_map(map) do
    # Try string key first, then atom key. Must use explicit nil check
    # because false/0 are valid values that would be falsy with ||
    value =
      case Map.fetch(map, key) do
        {:ok, v} -> v
        :error -> Map.get(map, String.to_atom(key))
      end

    get_nested_value(value, rest)
  end

  defp get_nested_value(_, _), do: nil

  # ============================================================================
  # Comparison
  # ============================================================================

  defp compare_values(actual, ">=", expected) when is_number(actual) and is_number(expected),
    do: actual >= expected

  defp compare_values(actual, "<=", expected) when is_number(actual) and is_number(expected),
    do: actual <= expected

  defp compare_values(actual, ">", expected) when is_number(actual) and is_number(expected),
    do: actual > expected

  defp compare_values(actual, "<", expected) when is_number(actual) and is_number(expected),
    do: actual < expected

  defp compare_values(actual, "==", expected), do: actual == expected
  defp compare_values(actual, "!=", expected), do: actual != expected

  # Type coercion for string comparisons with numbers
  defp compare_values(actual, op, expected) when is_binary(actual) do
    case Float.parse(actual) do
      {num, ""} -> compare_values(num, op, expected)
      _ -> compare_values_fallback(actual, op, expected)
    end
  end

  defp compare_values(actual, op, expected) when is_binary(expected) do
    case Float.parse(expected) do
      {num, ""} -> compare_values(actual, op, num)
      _ -> compare_values_fallback(actual, op, expected)
    end
  end

  defp compare_values(actual, op, expected), do: compare_values_fallback(actual, op, expected)

  defp compare_values_fallback(actual, "==", expected), do: actual == expected
  defp compare_values_fallback(actual, "!=", expected), do: actual != expected
  defp compare_values_fallback(_, _, _), do: false
end
