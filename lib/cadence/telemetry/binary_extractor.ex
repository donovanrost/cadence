defmodule Cadence.Telemetry.BinaryExtractor do
  @moduledoc """
  Low-level binary field extraction for telemetry decommutation.

  Handles bit-level extraction of telemetry items from packet payloads, supporting:
  - Bit-aligned and byte-aligned fields
  - Multiple data types (uint, int, float, string, block)
  - Big-endian and little-endian byte order
  - Variable-length strings
  - Nested/derived items

  This module follows COSMOS conventions for binary packet parsing.

  ## Data Types

  - `:uint` - Unsigned integer (8, 16, 32, 64 bits)
  - `:int` - Signed integer (8, 16, 32, 64 bits)
  - `:float` - IEEE 754 floating point (32 or 64 bits)
  - `:string` - Fixed or variable-length ASCII/UTF-8 string
  - `:block` - Raw binary data block

  ## Endianness

  - `:big_endian` - Network byte order (default for CCSDS)
  - `:little_endian` - Intel byte order

  ## Examples

      # Extract 16-bit big-endian unsigned integer at bit offset 0
      iex> extract(<<0x12, 0x34, 0x56>>, 0, 16, :uint, :big_endian)
      {:ok, 0x1234}

      # Extract 16-bit little-endian unsigned integer at bit offset 0
      iex> extract(<<0x34, 0x12, 0x56>>, 0, 16, :uint, :little_endian)
      {:ok, 0x1234}

      # Extract 8-bit signed integer
      iex> extract(<<0xFF, 0x00>>, 0, 8, :int, :big_endian)
      {:ok, -1}

      # Extract 32-bit float
      iex> extract(<<0x40, 0x49, 0x0F, 0xDB>>, 0, 32, :float, :big_endian)
      {:ok, 3.1415927410125732}

      # Extract 10-character string
      iex> extract(<<"Hello     ", 0x00>>, 0, 80, :string, :big_endian)
      {:ok, "Hello"}

      # Extract non-byte-aligned field (12 bits at offset 4)
      iex> extract(<<0x0A, 0xBC, 0x00>>, 4, 12, :uint, :big_endian)
      {:ok, 0xABC}
  """

  import Bitwise

  @doc """
  Extracts a field from a binary payload.

  ## Parameters

  - `binary` - The binary payload
  - `bit_offset` - Bit offset from the start of the payload (0-indexed)
  - `bit_size` - Size of the field in bits
  - `data_type` - Data type (`:uint`, `:int`, `:float`, `:string`, `:block`)
  - `endianness` - Byte order (`:big_endian` or `:little_endian`)

  ## Returns

  - `{:ok, value}` - Extracted value
  - `{:error, reason}` - Extraction failed
  """
  def extract(binary, bit_offset, bit_size, data_type, endianness \\ :big_endian)

  # Fast path: byte-aligned extraction
  def extract(binary, bit_offset, bit_size, data_type, endianness)
      when rem(bit_offset, 8) == 0 and rem(bit_size, 8) == 0 do
    byte_offset = div(bit_offset, 8)
    field_byte_size = div(bit_size, 8)

    if byte_offset + field_byte_size <= Kernel.byte_size(binary) do
      <<_skip::binary-size(byte_offset), value::binary-size(field_byte_size), _rest::binary>> = binary
      decode_value(value, data_type, endianness)
    else
      {:error, :insufficient_data}
    end
  end

  # Slow path: bit-aligned extraction (requires bitstring operations)
  def extract(binary, bit_offset, bit_size, data_type, endianness) do
    total_bits = bit_size(binary)

    if bit_offset + bit_size <= total_bits do
      <<_skip::size(bit_offset), value::bitstring-size(bit_size), _rest::bitstring>> = binary

      # Convert bitstring to binary (pad to byte boundary if needed)
      padding = rem(8 - rem(bit_size, 8), 8)
      padded_value = <<value::bitstring, 0::size(padding)>>

      decode_value(padded_value, data_type, endianness, bit_size)
    else
      {:error, :insufficient_data}
    end
  end

  ## Private Functions - Decoding

  # Decode byte-aligned values (fast path)
  defp decode_value(binary, :uint, :big_endian) do
    {:ok, :binary.decode_unsigned(binary, :big)}
  end

  defp decode_value(binary, :uint, :little_endian) do
    {:ok, :binary.decode_unsigned(binary, :little)}
  end

  defp decode_value(binary, :int, :big_endian) do
    unsigned = :binary.decode_unsigned(binary, :big)
    bit_size = byte_size(binary) * 8
    {:ok, to_signed(unsigned, bit_size)}
  end

  defp decode_value(binary, :int, :little_endian) do
    unsigned = :binary.decode_unsigned(binary, :little)
    bit_size = byte_size(binary) * 8
    {:ok, to_signed(unsigned, bit_size)}
  end

  defp decode_value(binary, :float, :big_endian) do
    case byte_size(binary) do
      4 -> <<value::float-32-big>> = binary; {:ok, value}
      8 -> <<value::float-64-big>> = binary; {:ok, value}
      _ -> {:error, :invalid_float_size}
    end
  end

  defp decode_value(binary, :float, :little_endian) do
    case byte_size(binary) do
      4 -> <<value::float-32-little>> = binary; {:ok, value}
      8 -> <<value::float-64-little>> = binary; {:ok, value}
      _ -> {:error, :invalid_float_size}
    end
  end

  defp decode_value(binary, :string, _endianness) do
    # Trim trailing null bytes and whitespace
    trimmed = binary |> String.trim_trailing(<<0>>) |> String.trim()
    {:ok, trimmed}
  end

  defp decode_value(binary, :block, _endianness) do
    # Return raw binary
    {:ok, binary}
  end

  # Decode bit-aligned values (slow path)
  defp decode_value(binary, :uint, :big_endian, actual_bit_size) do
    # For bit-aligned extraction, shift right to remove padding
    unsigned = :binary.decode_unsigned(binary, :big)
    padding = rem(8 - rem(actual_bit_size, 8), 8)
    value = unsigned >>> padding
    {:ok, value}
  end

  defp decode_value(binary, :uint, :little_endian, actual_bit_size) do
    # Little-endian bit-aligned is complex - reverse bytes then shift
    unsigned = :binary.decode_unsigned(binary, :little)
    padding = rem(8 - rem(actual_bit_size, 8), 8)
    # Note: Little-endian bit alignment is rarely used in spacecraft
    value = unsigned >>> padding
    {:ok, value}
  end

  defp decode_value(binary, :int, :big_endian, actual_bit_size) do
    {:ok, unsigned} = decode_value(binary, :uint, :big_endian, actual_bit_size)
    {:ok, to_signed(unsigned, actual_bit_size)}
  end

  defp decode_value(binary, :int, :little_endian, actual_bit_size) do
    {:ok, unsigned} = decode_value(binary, :uint, :little_endian, actual_bit_size)
    {:ok, to_signed(unsigned, actual_bit_size)}
  end

  defp decode_value(binary, :float, endianness, _actual_bit_size) do
    # Floats must be byte-aligned (32 or 64 bits)
    decode_value(binary, :float, endianness)
  end

  defp decode_value(binary, :string, endianness, _actual_bit_size) do
    decode_value(binary, :string, endianness)
  end

  defp decode_value(binary, :block, endianness, _actual_bit_size) do
    decode_value(binary, :block, endianness)
  end

  # Convert unsigned to signed using two's complement
  defp to_signed(unsigned, bit_size) do
    max_unsigned = 1 <<< bit_size
    sign_bit = 1 <<< (bit_size - 1)

    if (unsigned &&& sign_bit) != 0 do
      # Negative number
      unsigned - max_unsigned
    else
      # Positive number
      unsigned
    end
  end

  @doc """
  Extracts multiple fields from a binary payload.

  More efficient than calling extract/5 multiple times for large packets.

  ## Parameters

  - `binary` - The binary payload
  - `field_specs` - List of field specifications

  Each field spec is a keyword list:
  - `name` - Field name (atom)
  - `bit_offset` - Bit offset from start
  - `bit_size` - Size in bits
  - `data_type` - Data type
  - `endianness` - Byte order (optional, defaults to :big_endian)

  ## Returns

  - `{:ok, %{field_name => value}}` - Map of extracted values
  - `{:error, {field_name, reason}}` - Extraction failed for a field

  ## Example

      fields = [
        [name: :mode, bit_offset: 0, bit_size: 8, data_type: :uint],
        [name: :temp, bit_offset: 8, bit_size: 16, data_type: :int],
        [name: :voltage, bit_offset: 24, bit_size: 32, data_type: :float]
      ]

      extract_fields(packet_data, fields)
      # => {:ok, %{mode: 1, temp: 298, voltage: 28.5}}
  """
  def extract_fields(binary, field_specs) do
    Enum.reduce_while(field_specs, {:ok, %{}}, fn spec, {:ok, acc} ->
      # Use map pattern matching for O(1) access instead of Keyword.fetch! O(n)
      %{
        name: name,
        bit_offset: bit_offset,
        bit_size: bit_size,
        data_type: data_type,
        endianness: endianness
      } = spec

      case extract(binary, bit_offset, bit_size, data_type, endianness) do
        {:ok, value} ->
          {:cont, {:ok, Map.put(acc, name, value)}}

        {:error, reason} ->
          {:halt, {:error, {name, reason}}}
      end
    end)
  end

  @doc """
  Validates that a binary has sufficient size for extraction.

  Returns `:ok` if extraction is possible, `{:error, :insufficient_data}` otherwise.
  """
  def validate_size(binary, bit_offset, bit_size) do
    total_bits = bit_size(binary)

    if bit_offset + bit_size <= total_bits do
      :ok
    else
      {:error, :insufficient_data}
    end
  end

  @doc """
  Calculates the byte size needed to store a given number of bits.
  """
  def bits_to_bytes(bit_size) do
    div(bit_size + 7, 8)
  end
end
