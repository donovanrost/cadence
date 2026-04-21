defmodule Cadence.Telemetry.Extractor do
  @moduledoc """
  Bit-level extraction for definition-bound telemetry packets.
  """

  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @spec extract(binary(), PacketDefinition.t()) ::
          {:ok, [{FieldDefinition.t(), term()}]} | {:error, term()}
  def extract(packet_data, %PacketDefinition{} = packet_definition) when is_binary(packet_data) do
    packet_definition.fields
    |> Enum.reduce_while({:ok, []}, fn %FieldDefinition{} = field, {:ok, acc} ->
      case extract_field(packet_data, field) do
        {:ok, value} -> {:cont, {:ok, [{field, value} | acc]}}
        {:error, reason} -> {:halt, {:error, {field.name, reason}}}
      end
    end)
    |> case do
      {:ok, extracted} -> {:ok, Enum.reverse(extracted)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_field(packet_data, %FieldDefinition{} = field) do
    total_bits = bit_size(packet_data)
    end_offset = field.offset_bits + field.size_bits

    cond do
      field.size_bits <= 0 ->
        {:error, :invalid_size}

      end_offset > total_bits ->
        {:error, {:field_out_of_bounds, end_offset, total_bits}}

      true ->
        prefix_size = field.offset_bits
        suffix_size = total_bits - end_offset

        <<
          _::size(prefix_size),
          value_bits::bitstring-size(field.size_bits),
          _::size(suffix_size)
        >> = packet_data

        decode_value(value_bits, field)
    end
  end

  defp decode_value(value_bits, %FieldDefinition{data_type: :uint} = field) do
    decode_integer(value_bits, field.size_bits, :unsigned, field.byte_order, field.offset_bits)
  end

  defp decode_value(value_bits, %FieldDefinition{data_type: :int} = field) do
    decode_integer(value_bits, field.size_bits, :signed, field.byte_order, field.offset_bits)
  end

  defp decode_value(value_bits, %FieldDefinition{data_type: :float, size_bits: 32} = field) do
    decode_float(value_bits, 32, field.byte_order, field.offset_bits)
  end

  defp decode_value(value_bits, %FieldDefinition{data_type: :float, size_bits: 64} = field) do
    decode_float(value_bits, 64, field.byte_order, field.offset_bits)
  end

  defp decode_value(_value_bits, %FieldDefinition{data_type: :float}),
    do: {:error, :float_requires_32_or_64_bits}

  defp decode_value(value_bits, %FieldDefinition{data_type: :bool, size_bits: 1}) do
    <<value::unsigned-integer-size(1)>> = value_bits
    {:ok, value == 1}
  end

  defp decode_value(_value_bits, %FieldDefinition{data_type: :bool}),
    do: {:error, :bool_requires_one_bit}

  defp decode_value(_value_bits, %FieldDefinition{data_type: data_type}),
    do: {:error, {:unsupported_data_type, data_type}}

  defp decode_integer(value_bits, size_bits, sign_mode, :little_endian, offset_bits) do
    if little_endian_decode_requires_byte_alignment?(offset_bits, size_bits) do
      {:error, {:little_endian_requires_byte_alignment, offset_bits, size_bits}}
    else
      value =
        case sign_mode do
          :unsigned ->
            <<decoded::little-unsigned-size(size_bits)>> = value_bits
            decoded

          :signed ->
            <<decoded::little-signed-size(size_bits)>> = value_bits
            decoded
        end

      {:ok, value}
    end
  end

  defp decode_integer(value_bits, size_bits, sign_mode, _byte_order, _offset_bits) do
    value =
      case sign_mode do
        :unsigned ->
          <<decoded::big-unsigned-size(size_bits)>> = value_bits
          decoded

        :signed ->
          <<decoded::big-signed-size(size_bits)>> = value_bits
          decoded
      end

    {:ok, value}
  end

  defp decode_float(value_bits, size_bits, :little_endian, offset_bits) do
    if little_endian_decode_requires_byte_alignment?(offset_bits, size_bits) do
      {:error, {:little_endian_requires_byte_alignment, offset_bits, size_bits}}
    else
      value =
        case size_bits do
          32 ->
            <<decoded::little-float-32>> = value_bits
            decoded

          64 ->
            <<decoded::little-float-64>> = value_bits
            decoded
        end

      {:ok, value}
    end
  end

  defp decode_float(value_bits, 32, _byte_order, _offset_bits) do
    <<value::big-float-32>> = value_bits
    {:ok, value}
  end

  defp decode_float(value_bits, 64, _byte_order, _offset_bits) do
    <<value::big-float-64>> = value_bits
    {:ok, value}
  end

  defp little_endian_decode_requires_byte_alignment?(offset_bits, size_bits)
       when is_integer(offset_bits) and is_integer(size_bits) and size_bits > 8 do
    rem(offset_bits, 8) != 0 or rem(size_bits, 8) != 0
  end

  defp little_endian_decode_requires_byte_alignment?(_offset_bits, _size_bits), do: false
end
