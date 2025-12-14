defmodule Cadence.Commands.Encoder do
  @moduledoc """
  Binary command encoding based on Argument specifications.

  Handles bit-level encoding of command arguments into binary payloads, supporting:
  - Bit-aligned and byte-aligned fields
  - Multiple data types (uint, int, float, string, boolean, enum)
  - Big-endian and little-endian byte order
  - Range validation during encoding

  This module is the inverse of BinaryExtractor - it takes values and packs them
  into binary format for transmission to spacecraft.

  ## Example

      command = %MetaCommand{opcode: 0x01, arguments: [...]}
      params = %{"mode" => 1, "target_temp" => 25.5}

      {:ok, binary} = Encoder.encode(command, params)
      # => <<0x00, 0x01, ...payload...>>
  """

  alias Cadence.MissionDatabase.{MetaCommand, Argument}

  # Valid data types that can be safely converted to atoms
  @valid_data_types %{
    "uint" => :uint,
    "int" => :int,
    "float" => :float,
    "string" => :string,
    "boolean" => :boolean,
    "enum" => :enum
  }

  @doc """
  Encodes a command with its arguments into binary format.

  Returns `{:ok, binary}` where binary is: `<<opcode::16, payload::binary>>`

  ## Parameters

  - `command` - MetaCommand struct with preloaded arguments
  - `params` - Map of argument name => value

  ## Returns

  - `{:ok, binary}` - Successfully encoded command
  - `{:error, {:validation, errors}}` - Argument validation failed
  - `{:error, {:encoding, arg_name, reason}}` - Encoding failed for an argument
  """
  @spec encode(MetaCommand.t(), map()) :: {:ok, binary()} | {:error, term()}
  def encode(%MetaCommand{} = command, params) when is_map(params) do
    with :ok <- validate_required_args(command.arguments, params),
         {:ok, payload} <- build_payload(command.arguments, params) do
      # Build command packet: opcode (2 bytes big-endian) + payload
      opcode = command.opcode || 0
      {:ok, <<opcode::big-unsigned-16, payload::binary>>}
    end
  end

  @doc """
  Encodes a single argument value to binary.

  ## Parameters

  - `arg` - Argument struct
  - `value` - The value to encode

  ## Returns

  - `{:ok, binary}` - Encoded value
  - `{:error, reason}` - Encoding failed
  """
  @spec encode_argument(Argument.t(), term()) :: {:ok, binary()} | {:error, term()}
  def encode_argument(%Argument{} = arg, value) do
    data_type = safe_data_type(arg.data_type_ref)
    bit_length = arg.bit_length || 0

    # Resolve enum values to their numeric representation
    resolved_value = resolve_enum_value(arg, value)

    encode_value(resolved_value, data_type, bit_length)
  end

  # Safely convert data type string to atom without creating new atoms
  defp safe_data_type(type) when is_binary(type) do
    Map.get(@valid_data_types, type) ||
      raise ArgumentError, "Invalid data type: #{inspect(type)}"
  end

  defp safe_data_type(type) when is_atom(type), do: type

  @doc """
  Calculates the total payload size in bytes from argument definitions.
  """
  @spec payload_size(list(Argument.t())) :: non_neg_integer()
  def payload_size(arguments) when is_list(arguments) do
    if Enum.empty?(arguments) do
      0
    else
      max_extent =
        arguments
        |> Enum.map(fn arg ->
          offset = arg.bit_offset || 0
          length = arg.bit_length || 0
          offset + length
        end)
        |> Enum.max()

      # Round up to nearest byte
      div(max_extent + 7, 8)
    end
  end

  ## Private Functions

  defp validate_required_args(arguments, params) do
    errors =
      arguments
      |> Enum.filter(fn arg -> arg.required end)
      |> Enum.reject(fn arg ->
        Map.has_key?(params, arg.name) || Map.has_key?(params, String.to_atom(arg.name))
      end)
      |> Enum.map(fn arg -> {arg.name, "is required"} end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, {:validation, errors}}
    end
  end

  defp build_payload(arguments, params) do
    # Sort arguments by bit_offset for proper packing
    sorted = Enum.sort_by(arguments, fn arg -> arg.bit_offset || 0 end)

    # Calculate total payload size
    total_bytes = payload_size(sorted)

    if total_bytes == 0 do
      {:ok, <<>>}
    else
      # Start with zero-filled buffer
      initial_buffer = <<0::size(total_bytes * 8)>>

      # Insert each argument value
      Enum.reduce_while(sorted, {:ok, initial_buffer}, fn arg, {:ok, buffer} ->
        value = get_arg_value(params, arg)

        case encode_and_insert(buffer, arg, value) do
          {:ok, new_buffer} -> {:cont, {:ok, new_buffer}}
          {:error, reason} -> {:halt, {:error, {:encoding, arg.name, reason}}}
        end
      end)
    end
  end

  defp get_arg_value(params, %Argument{} = arg) do
    # Try string key first, then atom key, then default
    value = Map.get(params, arg.name) || Map.get(params, String.to_atom(arg.name))

    if is_nil(value) do
      parse_default(arg.default_value, arg.data_type_ref)
    else
      value
    end
  end

  defp parse_default(nil, _data_type), do: nil
  defp parse_default("", _data_type), do: nil

  defp parse_default(default, data_type) when data_type in ["uint", "int"] do
    case Integer.parse(default) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_default(default, "float") do
    case Float.parse(default) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_default(default, "boolean") do
    String.downcase(default) in ["true", "1", "yes"]
  end

  defp parse_default(default, "enum"), do: default
  defp parse_default(default, "string"), do: default

  defp encode_and_insert(buffer, %Argument{} = arg, value) do
    if is_nil(value) do
      # Optional argument with no value - leave buffer unchanged
      {:ok, buffer}
    else
      case encode_argument(arg, value) do
        {:ok, encoded} ->
          bit_offset = arg.bit_offset || 0
          bit_length = arg.bit_length || 0
          {:ok, insert_bits(buffer, bit_offset, bit_length, encoded)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp resolve_enum_value(%Argument{data_type_ref: "enum", valid_values: valid_values}, value)
       when is_binary(value) and is_list(valid_values) do
    # Enum values in valid_values are stored as strings
    # Return the index of the value in the list
    case Enum.find_index(valid_values, &(&1 == value)) do
      nil -> value
      index -> index
    end
  end

  defp resolve_enum_value(_arg, value), do: value

  # Encode value based on data type
  defp encode_value(value, :uint, bit_length) when is_integer(value) and value >= 0 do
    {:ok, <<value::big-unsigned-size(bit_length)>>}
  end

  defp encode_value(value, :uint, _bit_length) when is_integer(value) do
    {:error, :negative_value_for_uint}
  end

  defp encode_value(value, :int, bit_length) when is_integer(value) do
    {:ok, <<value::big-signed-size(bit_length)>>}
  end

  defp encode_value(value, :float, 32) when is_number(value) do
    {:ok, <<value::big-float-32>>}
  end

  defp encode_value(value, :float, 64) when is_number(value) do
    {:ok, <<value::big-float-64>>}
  end

  defp encode_value(_value, :float, bit_length) do
    {:error, {:invalid_float_size, bit_length}}
  end

  defp encode_value(true, :boolean, bit_length), do: {:ok, <<1::size(bit_length)>>}
  defp encode_value(false, :boolean, bit_length), do: {:ok, <<0::size(bit_length)>>}

  defp encode_value(value, :boolean, bit_length) when is_integer(value) do
    {:ok, <<value::size(bit_length)>>}
  end

  defp encode_value(value, :enum, bit_length) when is_integer(value) do
    {:ok, <<value::big-unsigned-size(bit_length)>>}
  end

  defp encode_value(value, :string, bit_length) when is_binary(value) do
    byte_length = div(bit_length, 8)
    # Pad or truncate string to fit
    padded = String.pad_trailing(value, byte_length, <<0>>)
    truncated = binary_part(padded, 0, min(byte_size(padded), byte_length))
    {:ok, truncated}
  end

  defp encode_value(value, data_type, _bit_length) do
    {:error, {:type_mismatch, data_type, value}}
  end

  @doc """
  Inserts encoded bits into a binary buffer at the specified offset.

  Handles both byte-aligned and bit-aligned insertion.
  """
  @spec insert_bits(binary(), non_neg_integer(), non_neg_integer(), binary()) :: binary()
  def insert_bits(buffer, bit_offset, bit_length, value) when rem(bit_offset, 8) == 0 do
    # Fast path: byte-aligned insertion
    byte_offset = div(bit_offset, 8)

    # Extract the value bits (may need truncation if value is larger)
    value_bits = binary_to_bits(value, bit_length)

    # Split buffer at insertion point
    <<before::binary-size(byte_offset), _::bitstring-size(bit_length), rest::bitstring>> = buffer

    # Combine: before + value + rest
    result = <<before::binary, value_bits::bitstring-size(bit_length), rest::bitstring>>

    # Ensure result is byte-aligned binary
    pad_to_bytes(result)
  end

  def insert_bits(buffer, bit_offset, bit_length, value) do
    # Slow path: bit-aligned insertion
    value_bits = binary_to_bits(value, bit_length)

    <<before::bitstring-size(bit_offset), _::bitstring-size(bit_length), rest::bitstring>> =
      buffer

    result = <<before::bitstring, value_bits::bitstring-size(bit_length), rest::bitstring>>

    pad_to_bytes(result)
  end

  # Convert binary to bitstring, taking only the specified number of bits
  defp binary_to_bits(binary, bit_length) do
    total_bits = bit_size(binary)

    if total_bits >= bit_length do
      # Take the rightmost bits (for big-endian values)
      skip = total_bits - bit_length
      <<_::size(skip), bits::bitstring-size(bit_length)>> = binary
      bits
    else
      # Pad with leading zeros
      padding = bit_length - total_bits
      <<0::size(padding), binary::bitstring>>
    end
  end

  # Ensure binary is byte-aligned by padding
  defp pad_to_bytes(bitstring) do
    case rem(bit_size(bitstring), 8) do
      0 -> bitstring
      n -> <<bitstring::bitstring, 0::size(8 - n)>>
    end
  end
end
