defmodule Cadence.Persistence.JsonDocument do
  @moduledoc false

  @spec encode(term()) :: term()
  def encode(%DateTime{} = value), do: DateTime.to_iso8601(value)

  def encode(value)
      when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value

  def encode(value) when is_atom(value), do: Atom.to_string(value)
  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)
  def encode(%_{} = value), do: value |> Map.from_struct() |> encode()

  def encode(value) when is_tuple(value),
    do: %{"tuple" => value |> Tuple.to_list() |> Enum.map(&encode/1)}

  def encode(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      {to_string(key), encode(item)}
    end)
  end

  @spec wrap_value(term()) :: map()
  def wrap_value(value), do: %{"value" => encode(value)}

  @spec unwrap_value(map() | term()) :: term()
  def unwrap_value(%{"value" => value}), do: value
  def unwrap_value(value), do: value

  @spec wrap_items(list()) :: map()
  def wrap_items(items) when is_list(items), do: %{"items" => encode(items)}

  @spec unwrap_items(map() | list()) :: list()
  def unwrap_items(%{"items" => items}) when is_list(items), do: items
  def unwrap_items(items) when is_list(items), do: items
end
