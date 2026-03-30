defmodule Cadence.DerivedTelemetry.ExpressionParser do
  @moduledoc """
  NimbleParsec-based parser for pure derived telemetry expressions.
  """

  import NimbleParsec

  ws = ignore(ascii_string([?\s, ?\t, ?\n, ?\r], min: 0))

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

  identifier =
    ascii_char([?a..?z, ?A..?Z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})

  qualified_variable =
    identifier
    |> ignore(ascii_char([?.]))
    |> concat(identifier)
    |> reduce({__MODULE__, :make_variable, []})
    |> unwrap_and_tag(:variable)

  unqualified_variable =
    identifier
    |> unwrap_and_tag(:unqualified_variable)

  if_keyword =
    string("if") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])) |> replace(:if)

  then_keyword =
    string("then") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])) |> replace(:then)

  else_keyword =
    string("else") |> lookahead_not(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])) |> replace(:else)

  plus = concat(ws, ascii_char([?+]) |> replace(:add)) |> concat(ws)
  minus_op = concat(ws, ascii_char([?-]) |> replace(:subtract)) |> concat(ws)
  times = concat(ws, ascii_char([?*]) |> replace(:multiply)) |> concat(ws)
  divide = concat(ws, ascii_char([?/]) |> replace(:divide)) |> concat(ws)
  lparen = ascii_char([?(])
  rparen = ascii_char([?)])
  comma = ascii_char([?,])

  lte = concat(ws, string("<=") |> replace(:lte)) |> concat(ws)
  gte = concat(ws, string(">=") |> replace(:gte)) |> concat(ws)
  lt = concat(ws, string("<") |> lookahead_not(string("=")) |> replace(:lt)) |> concat(ws)
  gt = concat(ws, string(">") |> lookahead_not(string("=")) |> replace(:gt)) |> concat(ws)
  eq = concat(ws, string("==") |> replace(:eq)) |> concat(ws)
  neq = concat(ws, string("!=") |> replace(:neq)) |> concat(ws)

  comparison_op = choice([lte, gte, lt, gt, eq, neq])

  defcombinatorp(
    :primary,
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
  )

  defcombinatorp(
    :function_call,
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
  )

  defcombinatorp(
    :call_or_primary,
    choice([
      parsec(:function_call),
      parsec(:primary)
    ])
  )

  defcombinatorp(
    :unary,
    choice([
      concat(ws, ignore(ascii_char([?-])))
      |> concat(ws)
      |> parsec(:unary)
      |> tag(:negate),
      parsec(:call_or_primary)
    ])
  )

  defcombinatorp(
    :multiplicative,
    parsec(:unary)
    |> repeat(
      choice([times, divide])
      |> parsec(:unary)
    )
    |> reduce({__MODULE__, :build_binary_expr, []})
  )

  defcombinatorp(
    :additive,
    parsec(:multiplicative)
    |> repeat(
      choice([plus, minus_op])
      |> parsec(:multiplicative)
    )
    |> reduce({__MODULE__, :build_binary_expr, []})
  )

  defcombinatorp(
    :comparison,
    parsec(:additive)
    |> optional(
      comparison_op
      |> parsec(:additive)
    )
    |> reduce({__MODULE__, :build_comparison, []})
  )

  defcombinatorp(
    :conditional,
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
  )

  defcombinatorp(:expr, parsec(:conditional))

  defparsec(
    :parse_expression,
    concat(ws, parsec(:expr))
    |> concat(ws)
    |> eos()
  )

  def to_integer(chars) do
    chars
    |> List.to_string()
    |> String.to_integer()
  end

  def to_float(chars) do
    chars
    |> List.to_string()
    |> String.to_float()
  end

  @pure_functions ~w(abs sqrt pow round floor ceil min max clamp)

  def make_variable([packet, item]), do: "#{packet}.#{item}"
  def make_function([name | [args]]), do: {name, args}
  def make_conditional([condition, then_expr, else_expr]), do: {condition, then_expr, else_expr}

  def build_binary_expr([single]), do: single

  def build_binary_expr([left, op, right | rest]) do
    result = {op, left, right}
    build_binary_expr([result | rest])
  end

  def build_comparison([single]), do: single
  def build_comparison([left, op, right]), do: {:comparison, op, left, right}

  @spec parse(binary()) :: {:ok, term()} | {:error, term()}
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

  @spec extract_variables(binary()) :: {:ok, [binary()]} | {:error, term()}
  def extract_variables(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} -> {:ok, ast |> collect_variables() |> Enum.uniq()}
      {:error, _reason} = error -> error
    end
  end

  @stateful_functions MapSet.new([
                        "rolling_avg",
                        "rolling_min",
                        "rolling_max",
                        "stddev",
                        "rate",
                        "delta",
                        "count",
                        "elapsed"
                      ])

  @spec has_stateful_functions?(binary()) :: {:ok, boolean()} | {:error, term()}
  def has_stateful_functions?(expression) when is_binary(expression) do
    case parse(expression) do
      {:ok, ast} -> {:ok, ast_has_stateful?(ast)}
      {:error, _reason} = error -> error
    end
  end

  defp validate_ast(ast) do
    case find_unqualified_variables(ast) do
      [] -> validate_functions(ast)
      [first | _rest] -> {:error, {:unqualified_variable, first}}
    end
  end

  defp validate_functions(ast) do
    case find_unknown_function(ast) do
      nil -> {:ok, ast}
      function_name -> {:error, {:unknown_function, function_name}}
    end
  end

  defp find_unqualified_variables({:unqualified_variable, name}), do: [name]
  defp find_unqualified_variables({:variable, _name}), do: []
  defp find_unqualified_variables({:number, _value}), do: []
  defp find_unqualified_variables({:negate, [inner]}), do: find_unqualified_variables(inner)

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

  defp find_unqualified_variables(_), do: []

  defp find_unknown_function({:function, {name, args}}) do
    cond do
      MapSet.member?(@stateful_functions, name) ->
        Enum.find_value(args, &find_unknown_function/1)

      name in @pure_functions ->
        Enum.find_value(args, &find_unknown_function/1)

      true ->
        name
    end
  end

  defp find_unknown_function({:negate, [inner]}), do: find_unknown_function(inner)

  defp find_unknown_function({:conditional, {cond, then_expr, else_expr}}) do
    find_unknown_function(cond) ||
      find_unknown_function(then_expr) ||
      find_unknown_function(else_expr)
  end

  defp find_unknown_function({:comparison, _op, left, right}) do
    find_unknown_function(left) || find_unknown_function(right)
  end

  defp find_unknown_function({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    find_unknown_function(left) || find_unknown_function(right)
  end

  defp find_unknown_function(_), do: nil

  defp collect_variables({:variable, name}), do: [name]
  defp collect_variables({:number, _value}), do: []
  defp collect_variables({:negate, [inner]}), do: collect_variables(inner)

  defp collect_variables({:function, {_name, args}}) do
    Enum.flat_map(args, &collect_variables/1)
  end

  defp collect_variables({:conditional, {cond, then_expr, else_expr}}) do
    collect_variables(cond) ++ collect_variables(then_expr) ++ collect_variables(else_expr)
  end

  defp collect_variables({:comparison, _op, left, right}) do
    collect_variables(left) ++ collect_variables(right)
  end

  defp collect_variables({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    collect_variables(left) ++ collect_variables(right)
  end

  defp collect_variables(_), do: []

  defp ast_has_stateful?({:function, {name, args}}) do
    MapSet.member?(@stateful_functions, name) or Enum.any?(args, &ast_has_stateful?/1)
  end

  defp ast_has_stateful?({:negate, [inner]}), do: ast_has_stateful?(inner)

  defp ast_has_stateful?({:conditional, {cond, then_expr, else_expr}}) do
    ast_has_stateful?(cond) or ast_has_stateful?(then_expr) or ast_has_stateful?(else_expr)
  end

  defp ast_has_stateful?({:comparison, _op, left, right}) do
    ast_has_stateful?(left) or ast_has_stateful?(right)
  end

  defp ast_has_stateful?({_op, left, right}) when is_tuple(left) and is_tuple(right) do
    ast_has_stateful?(left) or ast_has_stateful?(right)
  end

  defp ast_has_stateful?(_), do: false
end
