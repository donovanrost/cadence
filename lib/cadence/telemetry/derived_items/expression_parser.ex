defmodule Cadence.Telemetry.DerivedItems.ExpressionParser do
  @moduledoc """
  NimbleParsec-based parser for derived telemetry expressions.

  ## Supported Grammar

  ```
  expr         → conditional | additive
  conditional  → "if" expr "then" expr "else" expr
  additive     → multiplicative (("+" | "-") multiplicative)*
  multiplicative → unary (("*" | "/") unary)*
  unary        → "-" unary | call
  call         → IDENT "(" args? ")" | primary
  args         → expr ("," expr)*
  primary      → NUMBER | VARIABLE | "(" expr ")"
  VARIABLE     → IDENT "." IDENT  (qualified name required)
  NUMBER       → integer | float
  ```

  ## Pure Functions

  These functions are stateless and computed fresh on each evaluation:

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

  These functions maintain state across evaluations, enabling time-series analysis:

  - `rolling_avg(x, window)` - rolling average over last N samples
  - `rolling_min(x, window)` - minimum value over last N samples
  - `rolling_max(x, window)` - maximum value over last N samples
  - `stddev(x, window)` - standard deviation over last N samples
  - `rate(x)` - rate of change per second (derivative)
  - `delta(x)` - difference from previous value
  - `count()` - count of evaluations (packet counter)
  - `elapsed()` - seconds since first evaluation

  Stateful functions automatically maintain their state in ETS and will return
  cached values when their source items haven't changed.

  ## Conditionals

  - `if CONDITION then VALUE_IF_TRUE else VALUE_IF_FALSE`
  - Condition is truthy if non-zero

  ## Example Expressions

      # Pure expressions
      HEALTH.cpu_temp * 1.8 + 32
      (POWER.voltage * POWER.current) / 1000
      abs(ATTITUDE.roll)
      max(THERMAL.temp1, THERMAL.temp2, THERMAL.temp3)
      if POWER.voltage < 11.0 then 1 else 0
      clamp(HEALTH.temp, 0, 100)

      # Stateful expressions
      rolling_avg(HEALTH.cpu_temp, 10)
      rate(POWER.bus_voltage)
      rolling_avg(THERMAL.temp1, 5) + rolling_avg(THERMAL.temp2, 5)
      if rate(POWER.voltage) < -0.5 then 1 else 0
  """

  import NimbleParsec

  # Whitespace combinator - ignored between tokens
  ws = ignore(ascii_string([?\s, ?\t, ?\n, ?\r], min: 0))

  # Numbers
  integer =
    optional(ascii_char([?-]))
    |> ascii_string([?0..?9], min: 1)
    |> reduce({__MODULE__, :to_integer, []})

  float =
    optional(ascii_char([?-]))
    |> ascii_string([?0..?9], min: 1)
    |> ascii_char([?.])
    |> ascii_string([?0..?9], min: 1)
    |> reduce({__MODULE__, :to_float, []})

  number =
    choice([float, integer])
    |> unwrap_and_tag(:number)

  # Identifiers (for function names and variable parts)
  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})

  # Qualified variable: PACKET.item_name
  qualified_variable =
    identifier
    |> ignore(ascii_char([?.]))
    |> concat(identifier)
    |> reduce({__MODULE__, :make_variable, []})
    |> unwrap_and_tag(:variable)

  # Unqualified variable (for error reporting)
  unqualified_variable =
    identifier
    |> unwrap_and_tag(:unqualified_variable)

  # Keywords for conditionals (with lookahead to not match as identifier)
  if_keyword = string("if") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])) |> replace(:if)
  then_keyword = string("then") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])) |> replace(:then)
  else_keyword = string("else") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])) |> replace(:else)

  # Operators with whitespace handling
  plus = concat(ws, ascii_char([?+]) |> replace(:add)) |> concat(ws)
  minus_op = concat(ws, ascii_char([?-]) |> replace(:subtract)) |> concat(ws)
  times = concat(ws, ascii_char([?*]) |> replace(:multiply)) |> concat(ws)
  divide = concat(ws, ascii_char([?/]) |> replace(:divide)) |> concat(ws)
  lparen = ascii_char([?(])
  rparen = ascii_char([?)])
  comma = ascii_char([?,])

  # Comparison operators (for conditionals)
  lte = concat(ws, string("<=") |> replace(:lte)) |> concat(ws)
  gte = concat(ws, string(">=") |> replace(:gte)) |> concat(ws)
  lt = concat(ws, string("<") |> lookahead_not(string("=")) |> replace(:lt)) |> concat(ws)
  gt = concat(ws, string(">") |> lookahead_not(string("=")) |> replace(:gt)) |> concat(ws)
  eq = concat(ws, string("==") |> replace(:eq)) |> concat(ws)
  neq = concat(ws, string("!=") |> replace(:neq)) |> concat(ws)

  comparison_op = choice([lte, gte, lt, gt, eq, neq])

  # Primary expressions (atoms of the grammar)
  # Order matters: try qualified_variable before unqualified to get better errors
  defcombinatorp :primary,
    choice([
      number,
      concat(ws, ignore(lparen))
      |> concat(ws)
      |> parsec(:expr)
      |> concat(ws)
      |> ignore(rparen)
      |> concat(ws),
      qualified_variable,
      unqualified_variable
    ])

  # Function call: func_name(arg1, arg2, ...)
  defcombinatorp :function_call,
    identifier
    |> concat(ws)
    |> ignore(lparen)
    |> concat(ws)
    |> wrap(
      optional(
        parsec(:expr)
        |> repeat(
          concat(ws, ignore(comma))
          |> concat(ws)
          |> parsec(:expr)
        )
      )
    )
    |> concat(ws)
    |> ignore(rparen)
    |> reduce({__MODULE__, :make_function, []})
    |> unwrap_and_tag(:function)

  # Call or primary (function call takes precedence if followed by paren)
  defcombinatorp :call_or_primary,
    choice([
      parsec(:function_call),
      parsec(:primary)
    ])

  # Unary: -expr or call_or_primary
  defcombinatorp :unary,
    choice([
      concat(ws, ignore(ascii_char([?-])))
      |> concat(ws)
      |> parsec(:unary)
      |> tag(:negate),
      parsec(:call_or_primary)
    ])

  # Multiplicative: unary (("*" | "/") unary)*
  defcombinatorp :multiplicative,
    parsec(:unary)
    |> repeat(
      choice([times, divide])
      |> parsec(:unary)
    )
    |> reduce({__MODULE__, :build_binary_expr, []})

  # Additive: multiplicative (("+" | "-") multiplicative)*
  defcombinatorp :additive,
    parsec(:multiplicative)
    |> repeat(
      choice([plus, minus_op])
      |> parsec(:multiplicative)
    )
    |> reduce({__MODULE__, :build_binary_expr, []})

  # Comparison: additive (comp_op additive)?
  defcombinatorp :comparison,
    parsec(:additive)
    |> optional(
      comparison_op
      |> parsec(:additive)
    )
    |> reduce({__MODULE__, :build_comparison, []})

  # Conditional: "if" expr "then" expr "else" expr | comparison
  defcombinatorp :conditional,
    choice([
      concat(ws, ignore(if_keyword))
      |> concat(ws)
      |> parsec(:comparison)
      |> concat(ws)
      |> ignore(then_keyword)
      |> concat(ws)
      |> parsec(:expr)
      |> concat(ws)
      |> ignore(else_keyword)
      |> concat(ws)
      |> parsec(:expr)
      |> reduce({__MODULE__, :make_conditional, []})
      |> unwrap_and_tag(:conditional),
      parsec(:comparison)
    ])

  # Top-level expression
  defcombinatorp :expr, parsec(:conditional)

  # Main parser entry point
  defparsec :parse_expression,
    concat(ws, parsec(:expr))
    |> concat(ws)
    |> eos()

  # ============================================================================
  # Reducer Functions
  # ============================================================================

  @doc false
  def to_integer(chars) do
    chars
    |> List.to_string()
    |> String.to_integer()
  end

  @doc false
  def to_float(chars) do
    chars
    |> List.to_string()
    |> String.to_float()
  end

  @doc false
  def make_variable([packet, item]) do
    "#{packet}.#{item}"
  end

  @doc false
  def make_function([name | [args]]) do
    {String.to_atom(name), args}
  end

  @doc false
  def make_conditional([condition, then_expr, else_expr]) do
    {condition, then_expr, else_expr}
  end

  @doc false
  def build_binary_expr([single]) do
    single
  end

  def build_binary_expr([left, op, right | rest]) do
    result = {op, left, right}
    build_binary_expr([result | rest])
  end

  @doc false
  def build_comparison([single]) do
    single
  end

  def build_comparison([left, op, right]) do
    {:comparison, op, left, right}
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Parses an expression string into an AST.

  Returns `{:ok, ast}` or `{:error, reason}`.
  """
  def parse(expression) when is_binary(expression) do
    case parse_expression(expression) do
      {:ok, [ast], "", _, _, _} ->
        validate_ast(ast)

      {:ok, _, rest, _, _, _} ->
        {:error, {:unexpected_input, rest}}

      {:error, message, rest, _, {line, col}, _} ->
        {:error, {:parse_error, message, rest, line, col}}
    end
  end

  # Validate AST - check for unqualified variables
  defp validate_ast(ast) do
    case find_unqualified_variables(ast) do
      [] -> {:ok, ast}
      [first | _] -> {:error, {:unqualified_variable, first}}
    end
  end

  defp find_unqualified_variables({:unqualified_variable, name}) do
    [name]
  end

  defp find_unqualified_variables({:variable, _name}) do
    []
  end

  defp find_unqualified_variables({:number, _value}) do
    []
  end

  defp find_unqualified_variables({:negate, [inner]}) do
    find_unqualified_variables(inner)
  end

  defp find_unqualified_variables({:function, {_name, args}}) do
    Enum.flat_map(args, &find_unqualified_variables/1)
  end

  defp find_unqualified_variables({:conditional, {cond, then_expr, else_expr}}) do
    find_unqualified_variables(cond) ++
      find_unqualified_variables(then_expr) ++
      find_unqualified_variables(else_expr)
  end

  defp find_unqualified_variables({:comparison, _op, left, right}) do
    find_unqualified_variables(left) ++ find_unqualified_variables(right)
  end

  defp find_unqualified_variables({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    find_unqualified_variables(left) ++ find_unqualified_variables(right)
  end

  defp find_unqualified_variables(_) do
    []
  end

  @doc """
  Extracts all variable names from an expression.

  Returns `{:ok, variables}` or `{:error, reason}`.
  """
  def extract_variables(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} ->
        variables =
          ast
          |> collect_variables()
          |> Enum.uniq()

        {:ok, variables}

      {:error, _} = error ->
        error
    end
  end

  defp collect_variables({:variable, name}) do
    [name]
  end

  defp collect_variables({:number, _}) do
    []
  end

  defp collect_variables({:negate, [inner]}) do
    collect_variables(inner)
  end

  defp collect_variables({:function, {_name, args}}) do
    Enum.flat_map(args, &collect_variables/1)
  end

  defp collect_variables({:conditional, {cond, then_expr, else_expr}}) do
    collect_variables(cond) ++
      collect_variables(then_expr) ++
      collect_variables(else_expr)
  end

  defp collect_variables({:comparison, _op, left, right}) do
    collect_variables(left) ++ collect_variables(right)
  end

  defp collect_variables({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    collect_variables(left) ++ collect_variables(right)
  end

  defp collect_variables(_) do
    []
  end

  # ============================================================================
  # Stateful Function Detection
  # ============================================================================

  @stateful_functions MapSet.new([
    :rolling_avg,
    :rolling_min,
    :rolling_max,
    :stddev,
    :rate,
    :delta,
    :count,
    :elapsed
  ])

  @doc """
  Returns the set of stateful function names.

  Stateful functions maintain state across evaluations and require
  access to the ProcessorState ETS table.
  """
  @spec stateful_functions() :: MapSet.t(atom())
  def stateful_functions, do: @stateful_functions

  @doc """
  Checks if a function name is a stateful function.

  ## Examples

      iex> ExpressionParser.stateful_function?(:rolling_avg)
      true

      iex> ExpressionParser.stateful_function?(:abs)
      false
  """
  @spec stateful_function?(atom()) :: boolean()
  def stateful_function?(name) when is_atom(name) do
    MapSet.member?(@stateful_functions, name)
  end

  @doc """
  Checks if an expression contains any stateful functions.

  This is useful for determining whether an expression needs access to
  processor state during evaluation.

  ## Examples

      iex> ExpressionParser.has_stateful_functions?("rolling_avg(HEALTH.TEMP, 10)")
      {:ok, true}

      iex> ExpressionParser.has_stateful_functions?("HEALTH.TEMP1 + HEALTH.TEMP2")
      {:ok, false}
  """
  @spec has_stateful_functions?(String.t()) :: {:ok, boolean()} | {:error, term()}
  def has_stateful_functions?(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} ->
        {:ok, ast_has_stateful?(ast)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Checks if an AST contains any stateful functions.
  """
  @spec ast_has_stateful?(term()) :: boolean()
  def ast_has_stateful?({:function, {name, args}}) do
    stateful_function?(name) or Enum.any?(args, &ast_has_stateful?/1)
  end

  def ast_has_stateful?({:negate, [inner]}) do
    ast_has_stateful?(inner)
  end

  def ast_has_stateful?({:conditional, {cond, then_expr, else_expr}}) do
    ast_has_stateful?(cond) or ast_has_stateful?(then_expr) or ast_has_stateful?(else_expr)
  end

  def ast_has_stateful?({:comparison, _op, left, right}) do
    ast_has_stateful?(left) or ast_has_stateful?(right)
  end

  def ast_has_stateful?({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    ast_has_stateful?(left) or ast_has_stateful?(right)
  end

  def ast_has_stateful?(_), do: false

  @doc """
  Collects all stateful function calls from an expression.

  Returns a list of `{function_name, args_ast}` tuples for each stateful
  function call in the expression. Useful for pre-computing state keys.

  ## Examples

      iex> ExpressionParser.collect_stateful_calls("rolling_avg(HEALTH.T1, 10) + rate(HEALTH.T2)")
      {:ok, [{:rolling_avg, [...]}, {:rate, [...]}]}
  """
  @spec collect_stateful_calls(String.t()) :: {:ok, [{atom(), list()}]} | {:error, term()}
  def collect_stateful_calls(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} ->
        {:ok, do_collect_stateful_calls(ast)}

      {:error, _} = error ->
        error
    end
  end

  defp do_collect_stateful_calls({:function, {name, args}}) do
    nested = Enum.flat_map(args, &do_collect_stateful_calls/1)

    if stateful_function?(name) do
      [{name, args} | nested]
    else
      nested
    end
  end

  defp do_collect_stateful_calls({:negate, [inner]}) do
    do_collect_stateful_calls(inner)
  end

  defp do_collect_stateful_calls({:conditional, {cond, then_expr, else_expr}}) do
    do_collect_stateful_calls(cond) ++
      do_collect_stateful_calls(then_expr) ++
      do_collect_stateful_calls(else_expr)
  end

  defp do_collect_stateful_calls({:comparison, _op, left, right}) do
    do_collect_stateful_calls(left) ++ do_collect_stateful_calls(right)
  end

  defp do_collect_stateful_calls({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    do_collect_stateful_calls(left) ++ do_collect_stateful_calls(right)
  end

  defp do_collect_stateful_calls(_), do: []
end
