defmodule Cadence.Telemetry.DerivedItems.ExpressionEvaluator do
  @moduledoc """
  Safe expression evaluator for derived telemetry items.

  Parses and evaluates mathematical expressions with variable substitution.
  Uses NimbleParsec for robust parsing with proper operator precedence.

  ## Supported Operations

  - Arithmetic: `+`, `-`, `*`, `/`
  - Parentheses: `(`, `)`
  - Numeric literals: integers and floats
  - Variable references: MUST use qualified names (e.g., `HEALTH.battery_voltage`)

  ## Pure Functions

  - `abs(x)` - absolute value
  - `sqrt(x)` - square root
  - `min(a, b, ...)` - minimum (variadic)
  - `max(a, b, ...)` - maximum (variadic)
  - `pow(base, exp)` - exponentiation
  - `round(x)` - round to nearest integer
  - `floor(x)` - round down
  - `ceil(x)` - round up
  - `clamp(x, min, max)` - clamp value to range

  ## Stateful Functions (Processors)

  These functions maintain state across evaluations:

  - `rolling_avg(x, window)` - rolling average over last N samples
  - `rolling_min(x, window)` - minimum value over last N samples
  - `rolling_max(x, window)` - maximum value over last N samples
  - `stddev(x, window)` - standard deviation over last N samples
  - `rate(x)` - rate of change per second
  - `delta(x)` - difference from previous value
  - `count()` - count of evaluations
  - `elapsed()` - seconds since first evaluation

  ## Conditionals

  - `if CONDITION then VALUE_IF_TRUE else VALUE_IF_FALSE`
  - Comparison operators: `<`, `>`, `<=`, `>=`, `==`, `!=`
  - Condition is truthy if non-zero

  ## Qualified Names

  All variable names MUST be fully qualified in the format `PACKET.ITEM`:
  - `HEALTH.battery_voltage` - battery_voltage item from HEALTH packet
  - `POWER.bus_current` - bus_current item from POWER packet

  Unqualified names (e.g., just `battery_voltage`) will be rejected.

  ## Examples

      # Pure evaluation
      iex> ExpressionEvaluator.evaluate("HEALTH.TEMP1 + HEALTH.TEMP2", %{"HEALTH.TEMP1" => 25.0, "HEALTH.TEMP2" => 30.0})
      {:ok, 55.0}

      # Stateful evaluation (requires mission_id and item_name)
      iex> ExpressionEvaluator.evaluate_stateful("rolling_avg(HEALTH.TEMP, 10)", bindings, mission_id, "TEMP_AVG")
      {:ok, 25.5}
  """

  alias Cadence.Telemetry.DerivedItems.ExpressionParser
  alias Cadence.Telemetry.DerivedItems.ProcessorState

  @type bindings :: %{String.t() => number()}
  @type eval_result :: {:ok, number()} | {:error, term()}
  @type eval_context :: %{
          bindings: bindings(),
          mission_id: String.t() | nil,
          item_name: String.t() | nil
        }

  @doc """
  Evaluates an expression string with the given variable bindings.

  ## Parameters

  - `expression` - The expression string to evaluate
  - `bindings` - Map of variable names to values

  ## Returns

  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @spec evaluate(String.t(), bindings()) :: eval_result()
  def evaluate(expression, bindings) when is_binary(expression) and is_map(bindings) do
    with {:ok, ast} <- ExpressionParser.parse(expression),
         {:ok, result} <- eval_ast(ast, bindings) do
      {:ok, result}
    end
  end

  @doc """
  Evaluates a pre-parsed AST with the given variable bindings.

  This is the optimized hot path - use this when the expression has been
  parsed and cached ahead of time.

  ## Parameters

  - `ast` - Pre-parsed AST from ExpressionParser.parse/1
  - `bindings` - Map of variable names to values

  ## Returns

  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @spec evaluate_ast(term(), bindings()) :: eval_result()
  def evaluate_ast(ast, bindings) when is_map(bindings) do
    eval_ast(ast, bindings)
  end

  @doc """
  Validates an expression without evaluating it.

  Useful for checking expression syntax at definition time.
  """
  @spec validate(String.t()) :: :ok | {:error, term()}
  def validate(expression) when is_binary(expression) do
    case ExpressionParser.parse(expression) do
      {:ok, _ast} -> :ok
      error -> error
    end
  end

  @doc """
  Extracts variable names referenced in an expression.

  Useful for determining dependencies at definition time.
  """
  @spec extract_variables(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def extract_variables(expression) when is_binary(expression) do
    ExpressionParser.extract_variables(expression)
  end

  # ============================================================================
  # Stateful Evaluation API
  # ============================================================================

  @doc """
  Evaluates an expression with stateful function support.

  This is the entry point for expressions that may contain stateful functions
  like `rolling_avg`, `rate`, etc. State is read from and written to the
  ProcessorState ETS table.

  ## Parameters

  - `expression` - The expression string to evaluate
  - `bindings` - Map of variable names to values
  - `mission_id` - Mission ID for state scoping
  - `item_name` - Derived item name for state scoping

  ## Returns

  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @spec evaluate_stateful(String.t(), bindings(), String.t(), String.t()) :: eval_result()
  def evaluate_stateful(expression, bindings, mission_id, item_name)
      when is_binary(expression) and is_map(bindings) do
    with {:ok, ast} <- ExpressionParser.parse(expression) do
      evaluate_ast_stateful(ast, bindings, mission_id, item_name)
    end
  end

  @doc """
  Evaluates a pre-parsed AST with stateful function support.

  This is the optimized hot path for stateful evaluation - use when the
  expression has been parsed and cached ahead of time.

  ## Parameters

  - `ast` - Pre-parsed AST from ExpressionParser.parse/1
  - `bindings` - Map of variable names to values
  - `mission_id` - Mission ID for state scoping
  - `item_name` - Derived item name for state scoping

  ## Returns

  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @spec evaluate_ast_stateful(term(), bindings(), String.t(), String.t()) :: eval_result()
  def evaluate_ast_stateful(ast, bindings, mission_id, item_name) when is_map(bindings) do
    ctx = %{bindings: bindings, mission_id: mission_id, item_name: item_name}
    eval_ast_stateful(ast, ctx)
  end

  # ============================================================================
  # AST Evaluation (Pure - backward compatible)
  # ============================================================================

  # Literals
  defp eval_ast({:number, n}, _bindings), do: {:ok, n}

  # Variables
  defp eval_ast({:variable, name}, bindings) do
    case Map.fetch(bindings, name) do
      {:ok, value} when is_number(value) -> {:ok, value}
      {:ok, nil} -> {:error, {:nil_value, name}}
      {:ok, value} -> {:error, {:non_numeric_value, name, value}}
      :error -> {:error, {:undefined_variable, name}}
    end
  end

  # Unary negation
  defp eval_ast({:negate, [inner]}, bindings) do
    with {:ok, value} <- eval_ast(inner, bindings) do
      {:ok, -value}
    end
  end

  # Binary arithmetic operators
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

  # Comparison operators
  defp eval_ast({:comparison, op, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      result = compare(op, l, r)
      {:ok, if(result, do: 1, else: 0)}
    end
  end

  # Conditionals
  defp eval_ast({:conditional, {condition, then_expr, else_expr}}, bindings) do
    with {:ok, cond_value} <- eval_ast(condition, bindings) do
      # Truthy if non-zero
      if cond_value != 0 do
        eval_ast(then_expr, bindings)
      else
        eval_ast(else_expr, bindings)
      end
    end
  end

  # Function calls
  defp eval_ast({:function, {name, args}}, bindings) do
    # Evaluate all arguments first
    case eval_args(args, bindings) do
      {:ok, evaluated_args} ->
        apply_function(name, evaluated_args)

      error ->
        error
    end
  end

  # Helper functions for eval_ast
  defp compare(:lt, l, r), do: l < r
  defp compare(:gt, l, r), do: l > r
  defp compare(:lte, l, r), do: l <= r
  defp compare(:gte, l, r), do: l >= r
  defp compare(:eq, l, r), do: l == r
  defp compare(:neq, l, r), do: l != r

  defp eval_args(args, bindings) do
    # Use prepend + reverse pattern for O(n) instead of O(n²) appending
    case do_eval_args(args, bindings, []) do
      {:ok, reversed} -> {:ok, :lists.reverse(reversed)}
      error -> error
    end
  end

  defp do_eval_args([], _bindings, acc), do: {:ok, acc}

  defp do_eval_args([arg | rest], bindings, acc) do
    case eval_ast(arg, bindings) do
      {:ok, value} -> do_eval_args(rest, bindings, [value | acc])
      error -> error
    end
  end

  # ============================================================================
  # Built-in Functions
  # ============================================================================

  defp apply_function(:abs, [x]) when is_number(x), do: {:ok, abs(x)}
  defp apply_function(:abs, args), do: {:error, {:invalid_arity, :abs, 1, length(args)}}

  defp apply_function(:sqrt, [x]) when is_number(x) and x >= 0, do: {:ok, :math.sqrt(x)}
  defp apply_function(:sqrt, [x]) when is_number(x), do: {:error, {:domain_error, :sqrt, x}}
  defp apply_function(:sqrt, args), do: {:error, {:invalid_arity, :sqrt, 1, length(args)}}

  defp apply_function(:pow, [base, exp]) when is_number(base) and is_number(exp) do
    {:ok, :math.pow(base, exp)}
  end

  defp apply_function(:pow, args), do: {:error, {:invalid_arity, :pow, 2, length(args)}}

  defp apply_function(:round, [x]) when is_number(x), do: {:ok, round(x)}
  defp apply_function(:round, args), do: {:error, {:invalid_arity, :round, 1, length(args)}}

  defp apply_function(:floor, [x]) when is_number(x), do: {:ok, floor(x)}
  defp apply_function(:floor, args), do: {:error, {:invalid_arity, :floor, 1, length(args)}}

  defp apply_function(:ceil, [x]) when is_number(x), do: {:ok, ceil(x)}
  defp apply_function(:ceil, args), do: {:error, {:invalid_arity, :ceil, 1, length(args)}}

  # Variadic min - requires at least 2 arguments
  defp apply_function(:min, args) when length(args) >= 2 do
    {:ok, Enum.min(args)}
  end

  defp apply_function(:min, args), do: {:error, {:invalid_arity, :min, "2+", length(args)}}

  # Variadic max - requires at least 2 arguments
  defp apply_function(:max, args) when length(args) >= 2 do
    {:ok, Enum.max(args)}
  end

  defp apply_function(:max, args), do: {:error, {:invalid_arity, :max, "2+", length(args)}}

  # Clamp - requires exactly 3 arguments
  defp apply_function(:clamp, [x, min_val, max_val])
       when is_number(x) and is_number(min_val) and is_number(max_val) do
    clamped = x |> max(min_val) |> min(max_val)
    {:ok, clamped}
  end

  defp apply_function(:clamp, args), do: {:error, {:invalid_arity, :clamp, 3, length(args)}}

  # Unknown function
  defp apply_function(name, _args), do: {:error, {:unknown_function, name}}

  # ============================================================================
  # Stateful AST Evaluation
  # ============================================================================

  # Literals
  defp eval_ast_stateful({:number, n}, _ctx), do: {:ok, n}

  # Variables
  defp eval_ast_stateful({:variable, name}, ctx) do
    case Map.fetch(ctx.bindings, name) do
      {:ok, value} when is_number(value) -> {:ok, value}
      {:ok, nil} -> {:error, {:nil_value, name}}
      {:ok, value} -> {:error, {:non_numeric_value, name, value}}
      :error -> {:error, {:undefined_variable, name}}
    end
  end

  # Unary negation
  defp eval_ast_stateful({:negate, [inner]}, ctx) do
    with {:ok, value} <- eval_ast_stateful(inner, ctx) do
      {:ok, -value}
    end
  end

  # Binary arithmetic operators
  defp eval_ast_stateful({:add, left, right}, ctx) do
    with {:ok, l} <- eval_ast_stateful(left, ctx),
         {:ok, r} <- eval_ast_stateful(right, ctx) do
      {:ok, l + r}
    end
  end

  defp eval_ast_stateful({:subtract, left, right}, ctx) do
    with {:ok, l} <- eval_ast_stateful(left, ctx),
         {:ok, r} <- eval_ast_stateful(right, ctx) do
      {:ok, l - r}
    end
  end

  defp eval_ast_stateful({:multiply, left, right}, ctx) do
    with {:ok, l} <- eval_ast_stateful(left, ctx),
         {:ok, r} <- eval_ast_stateful(right, ctx) do
      {:ok, l * r}
    end
  end

  defp eval_ast_stateful({:divide, left, right}, ctx) do
    with {:ok, l} <- eval_ast_stateful(left, ctx),
         {:ok, r} <- eval_ast_stateful(right, ctx) do
      if r == 0 do
        {:error, :division_by_zero}
      else
        {:ok, l / r}
      end
    end
  end

  # Comparison operators
  defp eval_ast_stateful({:comparison, op, left, right}, ctx) do
    with {:ok, l} <- eval_ast_stateful(left, ctx),
         {:ok, r} <- eval_ast_stateful(right, ctx) do
      result = compare(op, l, r)
      {:ok, if(result, do: 1, else: 0)}
    end
  end

  # Conditionals
  defp eval_ast_stateful({:conditional, {condition, then_expr, else_expr}}, ctx) do
    with {:ok, cond_value} <- eval_ast_stateful(condition, ctx) do
      if cond_value != 0 do
        eval_ast_stateful(then_expr, ctx)
      else
        eval_ast_stateful(else_expr, ctx)
      end
    end
  end

  # Function calls - dispatch to stateful or pure handler
  defp eval_ast_stateful({:function, {name, args}}, ctx) do
    if ExpressionParser.stateful_function?(name) do
      apply_stateful_function(name, args, ctx)
    else
      # Pure function - evaluate args and apply
      case eval_args_stateful(args, ctx) do
        {:ok, evaluated_args} ->
          apply_function(name, evaluated_args)

        error ->
          error
      end
    end
  end

  defp eval_args_stateful(args, ctx) do
    # Use prepend + reverse pattern for O(n) instead of O(n²) appending
    case do_eval_args_stateful(args, ctx, []) do
      {:ok, reversed} -> {:ok, :lists.reverse(reversed)}
      error -> error
    end
  end

  defp do_eval_args_stateful([], _ctx, acc), do: {:ok, acc}

  defp do_eval_args_stateful([arg | rest], ctx, acc) do
    case eval_ast_stateful(arg, ctx) do
      {:ok, value} -> do_eval_args_stateful(rest, ctx, [value | acc])
      error -> error
    end
  end

  # ============================================================================
  # Stateful Function Implementations
  # ============================================================================

  # Generate a unique state key for a stateful function call
  defp state_key(item_name, fn_name, args_ast) do
    {item_name, {fn_name, :erlang.phash2(args_ast)}}
  end

  # rolling_avg(x, window) - Rolling average over last N samples
  defp apply_stateful_function(:rolling_avg, [expr, window_ast], ctx) do
    with {:ok, value} <- eval_ast_stateful(expr, ctx),
         {:ok, window} <- eval_ast_stateful(window_ast, ctx) do
      window = trunc(window)
      key = state_key(ctx.item_name, :rolling_avg, [expr, window_ast])

      state = ProcessorState.get(ctx.mission_id, key) || %{buffer: []}
      new_buffer = Enum.take([value | state.buffer], window)
      avg = Enum.sum(new_buffer) / length(new_buffer)

      ProcessorState.put(ctx.mission_id, key, %{buffer: new_buffer})
      {:ok, avg}
    end
  end

  defp apply_stateful_function(:rolling_avg, args, _ctx) do
    {:error, {:invalid_arity, :rolling_avg, 2, length(args)}}
  end

  # rolling_min(x, window) - Minimum over last N samples
  defp apply_stateful_function(:rolling_min, [expr, window_ast], ctx) do
    with {:ok, value} <- eval_ast_stateful(expr, ctx),
         {:ok, window} <- eval_ast_stateful(window_ast, ctx) do
      window = trunc(window)
      key = state_key(ctx.item_name, :rolling_min, [expr, window_ast])

      state = ProcessorState.get(ctx.mission_id, key) || %{buffer: []}
      new_buffer = Enum.take([value | state.buffer], window)
      min_val = Enum.min(new_buffer)

      ProcessorState.put(ctx.mission_id, key, %{buffer: new_buffer})
      {:ok, min_val}
    end
  end

  defp apply_stateful_function(:rolling_min, args, _ctx) do
    {:error, {:invalid_arity, :rolling_min, 2, length(args)}}
  end

  # rolling_max(x, window) - Maximum over last N samples
  defp apply_stateful_function(:rolling_max, [expr, window_ast], ctx) do
    with {:ok, value} <- eval_ast_stateful(expr, ctx),
         {:ok, window} <- eval_ast_stateful(window_ast, ctx) do
      window = trunc(window)
      key = state_key(ctx.item_name, :rolling_max, [expr, window_ast])

      state = ProcessorState.get(ctx.mission_id, key) || %{buffer: []}
      new_buffer = Enum.take([value | state.buffer], window)
      max_val = Enum.max(new_buffer)

      ProcessorState.put(ctx.mission_id, key, %{buffer: new_buffer})
      {:ok, max_val}
    end
  end

  defp apply_stateful_function(:rolling_max, args, _ctx) do
    {:error, {:invalid_arity, :rolling_max, 2, length(args)}}
  end

  # stddev(x, window) - Standard deviation over last N samples
  defp apply_stateful_function(:stddev, [expr, window_ast], ctx) do
    with {:ok, value} <- eval_ast_stateful(expr, ctx),
         {:ok, window} <- eval_ast_stateful(window_ast, ctx) do
      window = trunc(window)
      key = state_key(ctx.item_name, :stddev, [expr, window_ast])

      state = ProcessorState.get(ctx.mission_id, key) || %{buffer: []}
      new_buffer = Enum.take([value | state.buffer], window)

      stddev =
        if length(new_buffer) < 2 do
          0.0
        else
          mean = Enum.sum(new_buffer) / length(new_buffer)

          variance =
            Enum.sum(Enum.map(new_buffer, fn x -> (x - mean) * (x - mean) end)) /
              length(new_buffer)

          :math.sqrt(variance)
        end

      ProcessorState.put(ctx.mission_id, key, %{buffer: new_buffer})
      {:ok, stddev}
    end
  end

  defp apply_stateful_function(:stddev, args, _ctx) do
    {:error, {:invalid_arity, :stddev, 2, length(args)}}
  end

  # rate(x) - Rate of change per second (derivative)
  defp apply_stateful_function(:rate, [expr], ctx) do
    with {:ok, value} <- eval_ast_stateful(expr, ctx) do
      key = state_key(ctx.item_name, :rate, [expr])
      now = System.monotonic_time(:millisecond)

      state = ProcessorState.get(ctx.mission_id, key)

      {rate, new_state} =
        case state do
          nil ->
            # First sample - can't compute rate yet, return 0
            {0.0, %{last_value: value, last_time: now}}

          %{last_value: last_value, last_time: last_time} ->
            dt_seconds = (now - last_time) / 1000.0

            rate =
              if dt_seconds > 0 do
                (value - last_value) / dt_seconds
              else
                0.0
              end

            {rate, %{last_value: value, last_time: now}}
        end

      ProcessorState.put(ctx.mission_id, key, new_state)
      {:ok, rate}
    end
  end

  defp apply_stateful_function(:rate, args, _ctx) do
    {:error, {:invalid_arity, :rate, 1, length(args)}}
  end

  # delta(x) - Difference from previous value
  defp apply_stateful_function(:delta, [expr], ctx) do
    with {:ok, value} <- eval_ast_stateful(expr, ctx) do
      key = state_key(ctx.item_name, :delta, [expr])

      state = ProcessorState.get(ctx.mission_id, key)

      {delta, new_state} =
        case state do
          nil ->
            # First sample - no delta yet, return 0
            {0.0, %{last_value: value}}

          %{last_value: last_value} ->
            {value - last_value, %{last_value: value}}
        end

      ProcessorState.put(ctx.mission_id, key, new_state)
      {:ok, delta}
    end
  end

  defp apply_stateful_function(:delta, args, _ctx) do
    {:error, {:invalid_arity, :delta, 1, length(args)}}
  end

  # count() - Count of evaluations (packet counter)
  defp apply_stateful_function(:count, [], ctx) do
    key = state_key(ctx.item_name, :count, [])

    state = ProcessorState.get(ctx.mission_id, key) || %{count: 0}
    new_count = state.count + 1

    ProcessorState.put(ctx.mission_id, key, %{count: new_count})
    {:ok, new_count}
  end

  defp apply_stateful_function(:count, args, _ctx) do
    {:error, {:invalid_arity, :count, 0, length(args)}}
  end

  # elapsed() - Seconds since first evaluation
  defp apply_stateful_function(:elapsed, [], ctx) do
    key = state_key(ctx.item_name, :elapsed, [])
    now = System.monotonic_time(:millisecond)

    state = ProcessorState.get(ctx.mission_id, key)

    {elapsed, new_state} =
      case state do
        nil ->
          # First call - start the timer
          {0.0, %{start_time: now}}

        %{start_time: start_time} ->
          elapsed_seconds = (now - start_time) / 1000.0
          {elapsed_seconds, state}
      end

    ProcessorState.put(ctx.mission_id, key, new_state)
    {:ok, elapsed}
  end

  defp apply_stateful_function(:elapsed, args, _ctx) do
    {:error, {:invalid_arity, :elapsed, 0, length(args)}}
  end

  # Unknown stateful function (shouldn't happen if parser is correct)
  defp apply_stateful_function(name, _args, _ctx) do
    {:error, {:unknown_function, name}}
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  @doc """
  Formats an error into a user-friendly message string.

  ## Examples

      iex> format_error({:undefined_variable, "HEALTH.TEMP"})
      "Undefined variable: HEALTH.TEMP"

      iex> format_error({:unknown_function, :foo})
      "Unknown function: foo"
  """
  @spec format_error(term()) :: String.t()
  def format_error({:undefined_variable, name}) do
    "Undefined variable: #{name}"
  end

  def format_error({:nil_value, name}) do
    "Variable has nil value: #{name}"
  end

  def format_error({:non_numeric_value, name, value}) do
    "Variable #{name} has non-numeric value: #{inspect(value)}"
  end

  def format_error(:division_by_zero) do
    "Division by zero"
  end

  def format_error({:unknown_function, name}) do
    "Unknown function: #{name}. Supported pure functions: abs, sqrt, min, max, pow, round, floor, ceil, clamp. " <>
      "Supported stateful functions: rolling_avg, rolling_min, rolling_max, stddev, rate, delta, count, elapsed"
  end

  def format_error({:invalid_arity, func, expected, got}) do
    "Function #{func} expects #{expected} argument(s), got #{got}"
  end

  def format_error({:domain_error, :sqrt, value}) do
    "Cannot compute square root of negative number: #{value}"
  end

  def format_error({:unqualified_variable, name}) do
    "Unqualified variable: #{name}. Use PACKET.ITEM format (e.g., HEALTH.#{name})"
  end

  def format_error({:parse_error, message, rest, line, col}) do
    location = if line > 1, do: "line #{line}, column #{col}", else: "position #{col}"
    remaining = if byte_size(rest) > 20, do: String.slice(rest, 0, 20) <> "...", else: rest
    "Parse error at #{location}: #{message}. Remaining: \"#{remaining}\""
  end

  def format_error({:unexpected_input, rest}) do
    remaining = if byte_size(rest) > 20, do: String.slice(rest, 0, 20) <> "...", else: rest
    "Unexpected input: \"#{remaining}\""
  end

  def format_error(:missing_expression) do
    "Expression is empty or missing"
  end

  def format_error(other) do
    "Expression error: #{inspect(other)}"
  end
end
