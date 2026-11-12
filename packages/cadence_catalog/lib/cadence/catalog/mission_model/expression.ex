defmodule Cadence.Catalog.MissionModel.Expression do
  @moduledoc "Typed, data-only expression AST shared by semantic consumers."

  @type value_type :: :number | :boolean | :string | :any
  @type t :: %__MODULE__{node: term(), result_type: value_type()}

  @enforce_keys [:node, :result_type]
  defstruct @enforce_keys

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      node: attrs |> Map.get(:node, Map.get(attrs, "node")) |> decode_node(),
      result_type:
        attrs
        |> Map.get(:result_type, Map.get(attrs, "result_type", :any))
        |> normalize_atom()
    }
  end

  # An explicit list, not the atom table (2026-11-12 sweep).
  @value_types_by_name Map.new(~w(number boolean string any)a, &{Atom.to_string(&1), &1})

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    case Map.fetch(@value_types_by_name, value) do
      {:ok, atom} ->
        atom

      :error ->
        raise ArgumentError, "unknown mission model expression result_type: #{inspect(value)}"
    end
  end

  defp decode_node(%{"tuple" => items}) when is_list(items) do
    items
    |> Enum.map(&decode_node/1)
    |> List.to_tuple()
  end

  defp decode_node(items) when is_list(items), do: Enum.map(items, &decode_node/1)

  defp decode_node(value)
       when value in [
              "literal",
              "parameter",
              "not",
              "if",
              "call",
              "stateful",
              "+",
              "-",
              "*",
              "/",
              "<",
              "<=",
              ">",
              ">=",
              "==",
              "!=",
              "and",
              "or",
              "abs",
              "sqrt",
              "min",
              "max",
              "round",
              "floor",
              "ceil",
              "clamp",
              "delta",
              "rate",
              "rolling_avg",
              "rolling_min",
              "rolling_max"
            ],
       do: String.to_existing_atom(value)

  defp decode_node(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, decode_node(value)} end)

  defp decode_node(value), do: value
end
