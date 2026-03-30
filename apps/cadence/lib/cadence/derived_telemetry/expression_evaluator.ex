defmodule Cadence.DerivedTelemetry.ExpressionEvaluator do
  @moduledoc """
  Pure expression evaluator for derived telemetry definitions.
  """

  alias Cadence.DerivedTelemetry.ExpressionParser

  @type bindings :: %{binary() => number()}
  @type eval_result :: {:ok, number()} | {:error, term()}

  @spec validate(binary()) :: :ok | {:error, term()}
  def validate(expression) when is_binary(expression) do
    case ExpressionParser.parse(expression) do
      {:ok, _ast} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec evaluate(binary(), bindings()) :: eval_result()
  def evaluate(expression, bindings) when is_binary(expression) and is_map(bindings) do
    with {:ok, ast} <- ExpressionParser.parse(expression) do
      evaluate_ast(ast, bindings)
    end
  end

  @spec evaluate_ast(term(), bindings()) :: eval_result()
  def evaluate_ast(ast, bindings) when is_map(bindings) do
    eval_ast(ast, bindings)
  end

  defp eval_ast({:number, n}, _bindings), do: {:ok, n}

  defp eval_ast({:variable, name}, bindings) do
    case Map.fetch(bindings, name) do
      {:ok, value} when is_number(value) -> {:ok, value}
      {:ok, nil} -> {:error, {:nil_value, name}}
      {:ok, value} -> {:error, {:non_numeric_value, name, value}}
      :error -> {:error, {:undefined_variable, name}}
    end
  end

  defp eval_ast({:negate, [inner]}, bindings) do
    with {:ok, value} <- eval_ast(inner, bindings) do
      {:ok, -value}
    end
  end

  defp eval_ast({:add, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      {:ok, l + r}
    end
  end

  defp eval_ast({:subtract, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      {:ok, l - r}
    end
  end

  defp eval_ast({:multiply, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      {:ok, l * r}
    end
  end

  defp eval_ast({:divide, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      if r == 0 do
        {:error, :division_by_zero}
      else
        {:ok, l / r}
      end
    end
  end

  defp eval_ast({:comparison, op, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      {:ok, if(compare(op, l, r), do: 1, else: 0)}
    end
  end

  defp eval_ast({:conditional, {condition, then_expr, else_expr}}, bindings) do
    with {:ok, cond_value} <- eval_ast(condition, bindings) do
      if cond_value != 0 do
        eval_ast(then_expr, bindings)
      else
        eval_ast(else_expr, bindings)
      end
    end
  end

  defp eval_ast({:function, {name, args}}, bindings) do
    case eval_args(args, bindings) do
      {:ok, evaluated_args} -> apply_function(name, evaluated_args)
      {:error, reason} -> {:error, reason}
    end
  end

  defp compare(:lt, l, r), do: l < r
  defp compare(:gt, l, r), do: l > r
  defp compare(:lte, l, r), do: l <= r
  defp compare(:gte, l, r), do: l >= r
  defp compare(:eq, l, r), do: l == r
  defp compare(:neq, l, r), do: l != r

  defp eval_args(args, bindings) do
    case do_eval_args(args, bindings, []) do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_eval_args([], _bindings, acc), do: {:ok, acc}

  defp do_eval_args([arg | rest], bindings, acc) do
    case eval_ast(arg, bindings) do
      {:ok, value} -> do_eval_args(rest, bindings, [value | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_function("abs", [x]) when is_number(x), do: {:ok, abs(x)}
  defp apply_function("abs", args), do: {:error, {:invalid_arity, "abs", 1, length(args)}}

  defp apply_function("sqrt", [x]) when is_number(x) and x >= 0, do: {:ok, :math.sqrt(x)}
  defp apply_function("sqrt", [x]) when is_number(x), do: {:error, {:domain_error, "sqrt", x}}
  defp apply_function("sqrt", args), do: {:error, {:invalid_arity, "sqrt", 1, length(args)}}

  defp apply_function("pow", [base, exp]) when is_number(base) and is_number(exp) do
    {:ok, :math.pow(base, exp)}
  end

  defp apply_function("pow", args), do: {:error, {:invalid_arity, "pow", 2, length(args)}}

  defp apply_function("round", [x]) when is_number(x), do: {:ok, round(x)}
  defp apply_function("round", args), do: {:error, {:invalid_arity, "round", 1, length(args)}}

  defp apply_function("floor", [x]) when is_number(x), do: {:ok, floor(x)}
  defp apply_function("floor", args), do: {:error, {:invalid_arity, "floor", 1, length(args)}}

  defp apply_function("ceil", [x]) when is_number(x), do: {:ok, ceil(x)}
  defp apply_function("ceil", args), do: {:error, {:invalid_arity, "ceil", 1, length(args)}}

  defp apply_function("min", args) when length(args) >= 2, do: {:ok, Enum.min(args)}
  defp apply_function("min", args), do: {:error, {:invalid_arity, "min", "2+", length(args)}}

  defp apply_function("max", args) when length(args) >= 2, do: {:ok, Enum.max(args)}
  defp apply_function("max", args), do: {:error, {:invalid_arity, "max", "2+", length(args)}}

  defp apply_function("clamp", [x, min_val, max_val])
       when is_number(x) and is_number(min_val) and is_number(max_val) do
    {:ok, x |> max(min_val) |> min(max_val)}
  end

  defp apply_function("clamp", args), do: {:error, {:invalid_arity, "clamp", 3, length(args)}}
  defp apply_function(name, _args), do: {:error, {:unknown_function, name}}
end
