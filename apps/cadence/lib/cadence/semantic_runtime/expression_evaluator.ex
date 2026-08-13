defmodule Cadence.SemanticRuntime.ExpressionEvaluator do
  @moduledoc "Evaluator for the typed safe-core Mission Model expression AST."

  alias Cadence.Catalog.MissionModel.Expression

  @spec evaluate(Expression.t(), map(), map(), keyword()) ::
          {:ok, term(), map()} | {:error, term()}
  def evaluate(%Expression{} = expression, bindings, state \\ %{}, opts \\ [])
      when is_map(bindings) and is_map(state) and is_list(opts) do
    eval(expression.node, bindings, state, opts)
  end

  defp eval({:literal, value}, _bindings, state, _opts), do: {:ok, value, state}

  defp eval({:parameter, id}, bindings, state, _opts) do
    case Map.fetch(bindings, id) do
      {:ok, value} -> {:ok, value, state}
      :error -> {:error, {:missing_parameter, id}}
    end
  end

  defp eval({:not, expression}, bindings, state, opts) do
    with {:ok, value, next_state} <- eval(expression, bindings, state, opts) do
      {:ok, not truthy?(value), next_state}
    end
  end

  defp eval({:if, condition, on_true, on_false}, bindings, state, opts) do
    with {:ok, value, next_state} <- eval(condition, bindings, state, opts) do
      eval(if(truthy?(value), do: on_true, else: on_false), bindings, next_state, opts)
    end
  end

  defp eval({:call, function, arguments}, bindings, state, opts) do
    with {:ok, values, next_state} <- eval_many(arguments, bindings, state, opts) do
      apply_function(function, values, next_state)
    end
  end

  defp eval({:stateful, function, key, expression, settings}, bindings, state, opts) do
    with {:ok, value, next_state} <- eval(expression, bindings, state, opts) do
      apply_stateful(function, key, value, settings, next_state, opts)
    end
  end

  defp eval({operation, left, right}, bindings, state, opts)
       when operation in [:+, :-, :*, :/, :<, :<=, :>, :>=, :==, :!=, :and, :or] do
    with {:ok, left_value, left_state} <- eval(left, bindings, state, opts),
         {:ok, right_value, right_state} <- eval(right, bindings, left_state, opts) do
      apply_operation(operation, left_value, right_value, right_state)
    end
  end

  defp eval(%{"literal" => value}, bindings, state, opts),
    do: eval({:literal, value}, bindings, state, opts)

  defp eval(%{"parameter" => id}, bindings, state, opts),
    do: eval({:parameter, id}, bindings, state, opts)

  defp eval(node, _bindings, _state, _opts),
    do: {:error, {:unsupported_expression_node, node}}

  defp eval_many(nodes, bindings, state, opts) do
    Enum.reduce_while(nodes, {:ok, [], state}, fn node, {:ok, values, acc_state} ->
      case eval(node, bindings, acc_state, opts) do
        {:ok, value, next_state} -> {:cont, {:ok, [value | values], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values, next_state} -> {:ok, Enum.reverse(values), next_state}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_operation(:+, left, right, state), do: {:ok, left + right, state}
  defp apply_operation(:-, left, right, state), do: {:ok, left - right, state}
  defp apply_operation(:*, left, right, state), do: {:ok, left * right, state}
  defp apply_operation(:/, _left, 0, _state), do: {:error, :division_by_zero}
  defp apply_operation(:/, left, right, state), do: {:ok, left / right, state}
  defp apply_operation(:<, left, right, state), do: {:ok, left < right, state}
  defp apply_operation(:<=, left, right, state), do: {:ok, left <= right, state}
  defp apply_operation(:>, left, right, state), do: {:ok, left > right, state}
  defp apply_operation(:>=, left, right, state), do: {:ok, left >= right, state}
  defp apply_operation(:==, left, right, state), do: {:ok, left == right, state}
  defp apply_operation(:!=, left, right, state), do: {:ok, left != right, state}

  defp apply_operation(:and, left, right, state),
    do: {:ok, truthy?(left) and truthy?(right), state}

  defp apply_operation(:or, left, right, state), do: {:ok, truthy?(left) or truthy?(right), state}

  defp apply_function(:abs, [value], state), do: {:ok, abs(value), state}
  defp apply_function(:sqrt, [value], state) when value >= 0, do: {:ok, :math.sqrt(value), state}
  defp apply_function(:pow, [left, right], state), do: {:ok, :math.pow(left, right), state}
  defp apply_function(:min, values, state) when values != [], do: {:ok, Enum.min(values), state}
  defp apply_function(:max, values, state) when values != [], do: {:ok, Enum.max(values), state}
  defp apply_function(:round, [value], state), do: {:ok, round(value), state}
  defp apply_function(:floor, [value], state), do: {:ok, floor(value), state}
  defp apply_function(:ceil, [value], state), do: {:ok, ceil(value), state}

  defp apply_function(:clamp, [value, lower, upper], state),
    do: {:ok, value |> max(lower) |> min(upper), state}

  defp apply_function(function, values, _state),
    do: {:error, {:unsupported_function, function, length(values)}}

  defp apply_stateful(:delta, key, value, _settings, state, _opts) when is_number(value) do
    previous = Map.get(state, key)
    result = if is_map(previous), do: value - previous.value, else: 0
    {:ok, result, Map.put(state, key, %{value: value})}
  end

  defp apply_stateful(:rate, key, value, _settings, state, opts) when is_number(value) do
    at = Keyword.fetch!(opts, :at)
    previous = Map.get(state, key)

    result =
      case previous do
        %{value: old_value, at: %DateTime{} = old_at} ->
          elapsed = DateTime.diff(at, old_at, :microsecond) / 1_000_000
          if elapsed > 0, do: (value - old_value) / elapsed, else: 0

        _other ->
          0
      end

    {:ok, result, Map.put(state, key, %{value: value, at: at})}
  end

  defp apply_stateful(function, key, value, settings, state, _opts)
       when function in [:rolling_avg, :rolling_min, :rolling_max] and is_number(value) do
    size = max(setting(settings, :size, 1), 1)
    values = [value | Map.get(state, key, [])] |> Enum.take(size)

    result =
      case function do
        :rolling_avg -> Enum.sum(values) / length(values)
        :rolling_min -> Enum.min(values)
        :rolling_max -> Enum.max(values)
      end

    {:ok, result, Map.put(state, key, values)}
  end

  defp apply_stateful(function, _key, _value, _settings, _state, _opts),
    do: {:error, {:unsupported_stateful_function, function}}

  defp truthy?(false), do: false
  defp truthy?(nil), do: false
  defp truthy?(0), do: false
  defp truthy?(_value), do: true

  defp setting(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
