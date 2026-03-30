defmodule Cadence.Commanding.Encoder do
  @moduledoc """
  Runtime encoder for compiled command definitions.
  """

  alias Cadence.Catalog.Command.Compiler.{ArgumentSpec, EncodingStep, RuntimeDefinition}
  alias Cadence.Catalog.Command.TypeEncoding

  @spec encode(RuntimeDefinition.t(), map()) ::
          {:ok, %{binary: binary(), base64: binary(), size_bytes: non_neg_integer()}}
          | {:error, term()}
  def encode(%RuntimeDefinition{} = runtime_definition, resolved_argument_values)
      when is_map(resolved_argument_values) do
    with {:ok, argument_specs_by_id} <- argument_specs_by_id(runtime_definition),
         {:ok, layout_binary} <-
           encode_layout(runtime_definition, argument_specs_by_id, resolved_argument_values),
         {:ok, encoded_binary} <- prepend_opcode(runtime_definition, layout_binary) do
      {:ok,
       %{
         binary: encoded_binary,
         base64: Base.encode64(encoded_binary),
         size_bytes: byte_size(encoded_binary)
       }}
    end
  end

  defp argument_specs_by_id(%RuntimeDefinition{} = runtime_definition) do
    {:ok, Map.new(runtime_definition.argument_specs, &{&1.argument_id, &1})}
  end

  defp encode_layout(
         %RuntimeDefinition{} = runtime_definition,
         argument_specs_by_id,
         resolved_values
       ) do
    total_bits = total_layout_bits(runtime_definition)

    if total_bits == 0 do
      {:ok, <<>>}
    else
      initial_buffer = <<0::size(total_bits)>>

      runtime_definition.encoding_steps
      |> Enum.sort_by(&{&1.bit_offset, &1.display_order || &1.bit_offset})
      |> Enum.reduce_while({:ok, initial_buffer}, fn %EncodingStep{} = step, {:ok, buffer} ->
        case encode_step(step, argument_specs_by_id, resolved_values) do
          {:ok, encoded_value} ->
            {:cont, {:ok, insert_bits(buffer, step.bit_offset, step.size_bits, encoded_value)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, encoded} -> {:ok, pad_to_bytes(encoded)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp prepend_opcode(%RuntimeDefinition{opcode: nil}, layout_binary), do: {:ok, layout_binary}

  defp prepend_opcode(%RuntimeDefinition{} = runtime_definition, layout_binary) do
    opcode_size_bits = runtime_definition.opcode_size_bits || 8

    case encode_integer(runtime_definition.opcode, opcode_size_bits, :unsigned, :big_endian) do
      {:ok, opcode_binary} ->
        {:ok, pad_to_bytes(<<opcode_binary::bitstring, layout_binary::binary>>)}

      {:error, reason} ->
        {:error, {:command_opcode_encoding_failed, reason}}
    end
  end

  defp encode_step(
         %EncodingStep{step_kind: :fixed_value, fixed_value: fixed_value, size_bits: size_bits},
         _argument_specs_by_id,
         _resolved_values
       ) do
    encode_fixed_value(fixed_value, size_bits)
  end

  defp encode_step(
         %EncodingStep{step_kind: :argument_ref, argument_id: argument_id},
         argument_specs_by_id,
         resolved_values
       ) do
    with {:ok, %ArgumentSpec{} = argument_spec} <-
           fetch_argument_spec(argument_specs_by_id, argument_id),
         {:ok, value} <- fetch_resolved_value(resolved_values, argument_spec.name) do
      encode_argument_value(argument_spec, value)
    end
  end

  defp encode_step(%EncodingStep{} = step, _argument_specs_by_id, _resolved_values) do
    {:error, {:unsupported_command_encoding_step, step.step_kind}}
  end

  defp fetch_argument_spec(argument_specs_by_id, argument_id) do
    case Map.fetch(argument_specs_by_id, argument_id) do
      {:ok, %ArgumentSpec{} = argument_spec} -> {:ok, argument_spec}
      :error -> {:error, {:command_argument_spec_not_found, argument_id}}
    end
  end

  defp fetch_resolved_value(resolved_values, argument_name) do
    case Map.fetch(resolved_values, argument_name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:resolved_command_argument_not_found, argument_name}}
    end
  end

  defp encode_fixed_value(value, size_bits) when is_integer(size_bits) and size_bits > 0 do
    cond do
      is_integer(value) and value >= 0 ->
        encode_integer(value, size_bits, :unsigned, :big_endian)

      is_integer(value) ->
        encode_integer(value, size_bits, :signed, :big_endian)

      is_binary(value) ->
        encode_binary_value(value, size_bits)

      is_boolean(value) ->
        encode_boolean(value, size_bits)

      true ->
        {:error, {:unsupported_command_fixed_value, value, size_bits}}
    end
  end

  defp encode_argument_value(
         %ArgumentSpec{base_type: :integer, encoding: %TypeEncoding{} = encoding},
         value
       )
       when is_integer(value) do
    sign_mode = if encoding.signed, do: :signed, else: :unsigned
    encode_integer(value, encoding.size_bits, sign_mode, encoding.byte_order)
  end

  defp encode_argument_value(
         %ArgumentSpec{base_type: :float, encoding: %TypeEncoding{} = encoding},
         value
       )
       when is_number(value) do
    encode_float(value, encoding)
  end

  defp encode_argument_value(
         %ArgumentSpec{base_type: :string, encoding: %TypeEncoding{} = encoding},
         value
       )
       when is_binary(value) do
    encode_string(value, encoding)
  end

  defp encode_argument_value(
         %ArgumentSpec{base_type: :binary, encoding: %TypeEncoding{} = encoding},
         value
       )
       when is_binary(value) do
    encode_binary_value(value, encoding.size_bits)
  end

  defp encode_argument_value(
         %ArgumentSpec{base_type: :boolean, encoding: %TypeEncoding{} = encoding},
         value
       ) do
    encode_boolean(value, encoding.size_bits)
  end

  defp encode_argument_value(
         %ArgumentSpec{base_type: :enumerated, encoding: %TypeEncoding{} = encoding},
         value
       ) do
    with {:ok, integer_value} <- normalize_enumerated_value(value) do
      encode_integer(integer_value, encoding.size_bits, :unsigned, encoding.byte_order)
    end
  end

  defp encode_argument_value(%ArgumentSpec{} = argument_spec, value) do
    {:error,
     {:unsupported_command_argument_encoding, argument_spec.name, argument_spec.base_type, value}}
  end

  defp normalize_enumerated_value(value) when is_integer(value), do: {:ok, value}

  defp normalize_enumerated_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer_value, ""} -> {:ok, integer_value}
      _other -> {:error, {:invalid_enumerated_argument_value, value}}
    end
  end

  defp normalize_enumerated_value(value),
    do: {:error, {:invalid_enumerated_argument_value, value}}

  defp encode_integer(value, size_bits, :unsigned, byte_order)
       when is_integer(value) and is_integer(size_bits) and size_bits > 0 do
    cond do
      value < 0 ->
        {:error, {:negative_value_for_unsigned_integer, value, size_bits}}

      byte_order == :little_endian and rem(size_bits, 8) != 0 ->
        {:error, {:little_endian_non_byte_aligned_integer_unsupported, size_bits}}

      byte_order == :little_endian ->
        {:ok, <<value::little-unsigned-size(size_bits)>>}

      true ->
        {:ok, <<value::big-unsigned-size(size_bits)>>}
    end
  end

  defp encode_integer(value, size_bits, :signed, byte_order)
       when is_integer(value) and is_integer(size_bits) and size_bits > 0 do
    cond do
      byte_order == :little_endian and rem(size_bits, 8) != 0 ->
        {:error, {:little_endian_non_byte_aligned_integer_unsupported, size_bits}}

      byte_order == :little_endian ->
        {:ok, <<value::little-signed-size(size_bits)>>}

      true ->
        {:ok, <<value::big-signed-size(size_bits)>>}
    end
  end

  defp encode_float(value, %TypeEncoding{size_bits: 32, byte_order: :big_endian}),
    do: {:ok, <<value::big-float-32>>}

  defp encode_float(value, %TypeEncoding{size_bits: 32, byte_order: :little_endian}),
    do: {:ok, <<value::little-float-32>>}

  defp encode_float(value, %TypeEncoding{size_bits: 64, byte_order: :big_endian}),
    do: {:ok, <<value::big-float-64>>}

  defp encode_float(value, %TypeEncoding{size_bits: 64, byte_order: :little_endian}),
    do: {:ok, <<value::little-float-64>>}

  defp encode_float(_value, %TypeEncoding{} = encoding) do
    {:error, {:unsupported_command_float_encoding, encoding.size_bits, encoding.byte_order}}
  end

  defp encode_string(value, %TypeEncoding{size_bits: size_bits})
       when is_integer(size_bits) and size_bits > 0 and rem(size_bits, 8) == 0 do
    byte_length = div(size_bits, 8)
    padded_value = String.pad_trailing(value, byte_length, <<0>>)
    {:ok, binary_part(padded_value, 0, byte_length)}
  end

  defp encode_string(_value, %TypeEncoding{} = encoding) do
    {:error, {:unsupported_command_string_encoding, encoding.size_bits}}
  end

  defp encode_binary_value(value, size_bits)
       when is_binary(value) and is_integer(size_bits) and size_bits > 0 and
              rem(size_bits, 8) == 0 do
    byte_length = div(size_bits, 8)

    case byte_size(value) do
      ^byte_length -> {:ok, value}
      size when size < byte_length -> {:ok, value <> :binary.copy(<<0>>, byte_length - size)}
      _size -> {:ok, binary_part(value, 0, byte_length)}
    end
  end

  defp encode_binary_value(_value, size_bits) do
    {:error, {:unsupported_command_binary_encoding, size_bits}}
  end

  defp encode_boolean(true, size_bits) when is_integer(size_bits) and size_bits > 0,
    do: {:ok, <<1::size(size_bits)>>}

  defp encode_boolean(false, size_bits) when is_integer(size_bits) and size_bits > 0,
    do: {:ok, <<0::size(size_bits)>>}

  defp encode_boolean(value, size_bits)
       when is_integer(value) and is_integer(size_bits) and size_bits > 0,
       do: {:ok, <<value::size(size_bits)>>}

  defp encode_boolean(value, _size_bits), do: {:error, {:invalid_command_boolean_value, value}}

  defp total_layout_bits(%RuntimeDefinition{} = runtime_definition) do
    runtime_definition.size_bits ||
      Enum.reduce(runtime_definition.encoding_steps, 0, fn %EncodingStep{} = step, max_bits ->
        max(max_bits, step.bit_offset + step.size_bits)
      end)
  end

  defp insert_bits(buffer, bit_offset, bit_length, value) when rem(bit_offset, 8) == 0 do
    byte_offset = div(bit_offset, 8)
    value_bits = binary_to_bits(value, bit_length)

    <<before::binary-size(byte_offset), _::bitstring-size(bit_length), rest::bitstring>> = buffer

    pad_to_bytes(<<before::binary, value_bits::bitstring-size(bit_length), rest::bitstring>>)
  end

  defp insert_bits(buffer, bit_offset, bit_length, value) do
    value_bits = binary_to_bits(value, bit_length)

    <<before::bitstring-size(bit_offset), _::bitstring-size(bit_length), rest::bitstring>> =
      buffer

    pad_to_bytes(<<before::bitstring, value_bits::bitstring-size(bit_length), rest::bitstring>>)
  end

  defp binary_to_bits(binary, bit_length) do
    total_bits = bit_size(binary)

    if total_bits >= bit_length do
      skip = total_bits - bit_length
      <<_::size(skip), bits::bitstring-size(bit_length)>> = binary
      bits
    else
      padding = bit_length - total_bits
      <<0::size(padding), binary::bitstring>>
    end
  end

  defp pad_to_bytes(bitstring) do
    case rem(bit_size(bitstring), 8) do
      0 -> bitstring
      remainder -> <<bitstring::bitstring, 0::size(8 - remainder)>>
    end
  end
end
