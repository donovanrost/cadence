defmodule Cadence.Commands.Encoder do
  @moduledoc """
  Binary command encoding based on CommandParameter specifications.

  Handles bit-level encoding of command parameters into binary payloads, supporting:
  - Bit-aligned and byte-aligned fields
  - Multiple data types (uint, int, float, string, boolean, enum)
  - Big-endian and little-endian byte order
  - Range validation during encoding

  This module is the inverse of BinaryExtractor - it takes values and packs them
  into binary format for transmission to spacecraft.

  ## Example

      command = %CommandDefinition{opcode: 0x01, command_parameters: [...]}
      params = %{"mode" => 1, "target_temp" => 25.5}

      {:ok, binary} = Encoder.encode(command, params)
      # => <<0x00, 0x01, ...payload...>>
  """

  alias Cadence.Commands.{CommandDefinition, CommandParameter}

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
  Encodes a command with its parameters into binary format.

  Returns `{:ok, binary}` where binary is: `<<opcode::16, payload::binary>>`

  ## Parameters

  - `command` - CommandDefinition struct with preloaded command_parameters
  - `params` - Map of parameter name => value

  ## Returns

  - `{:ok, binary}` - Successfully encoded command
  - `{:error, {:validation, errors}}` - Parameter validation failed
  - `{:error, {:encoding, param_name, reason}}` - Encoding failed for a parameter
  """
  @spec encode(CommandDefinition.t(), map()) :: {:ok, binary()} | {:error, term()}
  def encode(%CommandDefinition{} = command, params) when is_map(params) do
    with :ok <- validate_required_params(command.command_parameters, params),
         {:ok, payload} <- build_payload(command.command_parameters, params) do
      # Build command packet: opcode (2 bytes big-endian) + payload
      opcode = command.opcode || 0
      {:ok, <<opcode::big-unsigned-16, payload::binary>>}
    end
  end

  @doc """
  Encodes a single parameter value to binary.

  ## Parameters

  - `param` - CommandParameter struct
  - `value` - The value to encode

  ## Returns

  - `{:ok, binary}` - Encoded value
  - `{:error, reason}` - Encoding failed
  """
  @spec encode_parameter(CommandParameter.t(), term()) :: {:ok, binary()} | {:error, term()}
  def encode_parameter(%CommandParameter{} = param, value) do
    data_type = safe_data_type(param.data_type)
    bit_length = param.bit_length || 0

    # Resolve enum values to their numeric representation
    resolved_value = resolve_enum_value(param, value)

    encode_value(resolved_value, data_type, bit_length)
  end

  # Safely convert data type string to atom without creating new atoms
  defp safe_data_type(type) when is_binary(type) do
    Map.get(@valid_data_types, type) ||
      raise ArgumentError, "Invalid data type: #{inspect(type)}"
  end

  defp safe_data_type(type) when is_atom(type), do: type

  @doc """
  Calculates the total payload size in bytes from parameter definitions.
  """
  @spec payload_size(list(CommandParameter.t())) :: non_neg_integer()
  def payload_size(parameters) when is_list(parameters) do
    if Enum.empty?(parameters) do
      0
    else
      max_extent =
        parameters
        |> Enum.map(fn p ->
          offset = p.bit_offset || 0
          length = p.bit_length || 0
          offset + length
        end)
        |> Enum.max()

      # Round up to nearest byte
      div(max_extent + 7, 8)
    end
  end

  ## Private Functions

  defp validate_required_params(parameters, params) do
    errors =
      parameters
      |> Enum.filter(&CommandParameter.required?/1)
      |> Enum.reject(fn param ->
        Map.has_key?(params, param.name) || Map.has_key?(params, String.to_atom(param.name))
      end)
      |> Enum.map(fn param -> {param.name, "is required"} end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, {:validation, errors}}
    end
  end

  defp build_payload(parameters, params) do
    # Sort parameters by bit_offset for proper packing
    sorted = Enum.sort_by(parameters, fn p -> p.bit_offset || 0 end)

    # Calculate total payload size
    total_bytes = payload_size(sorted)

    if total_bytes == 0 do
      {:ok, <<>>}
    else
      # Start with zero-filled buffer
      initial_buffer = <<0::size(total_bytes * 8)>>

      # Insert each parameter value
      Enum.reduce_while(sorted, {:ok, initial_buffer}, fn param, {:ok, buffer} ->
        value = get_param_value(params, param)

        case encode_and_insert(buffer, param, value) do
          {:ok, new_buffer} -> {:cont, {:ok, new_buffer}}
          {:error, reason} -> {:halt, {:error, {:encoding, param.name, reason}}}
        end
      end)
    end
  end

  defp get_param_value(params, %CommandParameter{} = param) do
    # Try string key first, then atom key, then default
    value = Map.get(params, param.name) || Map.get(params, String.to_atom(param.name))

    if is_nil(value) do
      parse_default(param.default_value, param.data_type)
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

  defp encode_and_insert(buffer, %CommandParameter{} = param, value) do
    if is_nil(value) do
      # Optional parameter with no value - leave buffer unchanged
      {:ok, buffer}
    else
      case encode_parameter(param, value) do
        {:ok, encoded} ->
          bit_offset = param.bit_offset || 0
          bit_length = param.bit_length || 0
          {:ok, insert_bits(buffer, bit_offset, bit_length, encoded)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp resolve_enum_value(%CommandParameter{data_type: "enum", valid_values: valid_values}, value)
       when is_binary(value) and is_list(valid_values) do
    # Enum values in valid_values are stored as strings
    # Return the index of the value in the list
    case Enum.find_index(valid_values, &(&1 == value)) do
      nil -> value
      index -> index
    end
  end

  defp resolve_enum_value(_param, value), do: value

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
