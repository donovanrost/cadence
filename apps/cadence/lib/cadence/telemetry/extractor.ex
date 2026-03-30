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

        decode_value(value_bits, field.data_type, field.size_bits)
    end
  end

  defp decode_value(value_bits, :uint, size_bits) do
    <<value::unsigned-integer-size(size_bits)>> = value_bits
    {:ok, value}
  end

  defp decode_value(value_bits, :int, size_bits) do
    <<value::signed-integer-size(size_bits)>> = value_bits
    {:ok, value}
  end

  defp decode_value(value_bits, :float, 32) do
    <<value::float-32>> = value_bits
    {:ok, value}
  end

  defp decode_value(value_bits, :float, 64) do
    <<value::float-64>> = value_bits
    {:ok, value}
  end

  defp decode_value(_value_bits, :float, _size_bits),
    do: {:error, :float_requires_32_or_64_bits}

  defp decode_value(value_bits, :bool, 1) do
    <<value::unsigned-integer-size(1)>> = value_bits
    {:ok, value == 1}
  end

  defp decode_value(_value_bits, :bool, _size_bits), do: {:error, :bool_requires_one_bit}

  defp decode_value(_value_bits, data_type, _size_bits),
    do: {:error, {:unsupported_data_type, data_type}}
end
