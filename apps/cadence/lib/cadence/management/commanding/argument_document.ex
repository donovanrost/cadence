defmodule Cadence.Management.Commanding.ArgumentDocument do
  @moduledoc "Bounded scalar argument JSON that preserves native integer precision."
  @max_bytes 32_768
  @max_arguments 64

  def decode(json, max_bytes \\ @max_bytes)

  def decode(json, max_bytes)
      when max_bytes in [32_768, 131_072] and is_binary(json) and byte_size(json) <= max_bytes do
    with {:ok, %Jason.OrderedObject{values: entries}} <-
           Jason.decode(json, objects: :ordered_objects),
         true <- length(entries) <= @max_arguments,
         true <-
           Enum.all?(entries, fn {key, value} -> name?(key) and scalar?(value, max_bytes) end),
         map = Map.new(entries),
         true <- map_size(map) == length(entries) do
      {:ok, map}
    else
      _ -> {:error, :invalid_command_arguments}
    end
  rescue
    _ -> {:error, :invalid_command_arguments}
  end

  def decode(_, _), do: {:error, :invalid_command_arguments}

  def encode!(arguments, max_bytes \\ @max_bytes)
      when is_map(arguments) and not is_struct(arguments) do
    encoded = Jason.encode!(arguments)

    case decode(encoded, max_bytes) do
      {:ok, ^arguments} -> encoded
      _ -> raise ArgumentError, "Invalid command argument document"
    end
  end

  defp name?(name), do: is_binary(name) and byte_size(name) in 1..240 and clean?(name)
  defp scalar?(value, _) when is_integer(value) or is_float(value) or is_boolean(value), do: true

  defp scalar?(value, max_bytes) when is_binary(value),
    do: byte_size(value) <= max_bytes and clean?(value)

  defp scalar?(_, _), do: false

  defp clean?(value),
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/, value)
end
