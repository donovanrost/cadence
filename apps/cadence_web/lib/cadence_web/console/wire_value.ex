defmodule CadenceWeb.Console.WireValue do
  @moduledoc """
  Encodes telemetry values for the console wire: numbers, strings, booleans
  and `nil` pass through unchanged; `Decimal` becomes a number; anything else
  (binaries that are not UTF-8, tuples, structs) becomes its inspected string so
  the client never receives an unencodable value.
  """

  @spec encode(term()) :: number() | binary() | boolean() | nil | list() | map()
  def encode(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  def encode(%Decimal{} = value), do: Decimal.to_float(value)

  def encode(value) when is_binary(value),
    do: if(String.valid?(value), do: value, else: inspect(value))

  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)

  def encode(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), encode(item)} end)

  def encode(value), do: inspect(value)
end
