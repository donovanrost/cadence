defmodule Cadence.Telemetry.CRC do
  @moduledoc """
  CRC and checksum calculation functions for packet validation.

  Supports common algorithms used in spacecraft communications:
  - CRC-32 (Ethernet, ZIP)
  - CRC-16-CCITT (CCSDS, X.25)
  - CRC-16-XMODEM
  - CRC-8
  - XOR checksum (simple byte XOR)

  ## Examples

      # Calculate CRC-16-CCITT
      Cadence.Telemetry.CRC.calculate(:crc16_ccitt, <<0x01, 0x02, 0x03>>)
      #=> 0x5F34

      # Calculate CRC-32
      Cadence.Telemetry.CRC.calculate(:crc32, "hello")
      #=> 0x3610A686
  """

  import Bitwise

  # CRC-16-CCITT lookup table (polynomial 0x1021, reflected)
  # Pre-computed for performance
  @crc16_ccitt_table (
    for byte <- 0..255 do
      Enum.reduce(0..7, byte <<< 8, fn _, crc ->
        if (crc &&& 0x8000) != 0 do
          bxor(crc <<< 1, 0x1021)
        else
          crc <<< 1
        end
        |> band(0xFFFF)
      end)
    end
    |> List.to_tuple()
  )

  # CRC-16-XMODEM lookup table (polynomial 0x1021, not reflected, init 0)
  @crc16_xmodem_table @crc16_ccitt_table

  # CRC-8 lookup table (polynomial 0x07)
  @crc8_table (
    for byte <- 0..255 do
      Enum.reduce(0..7, byte, fn _, crc ->
        if (crc &&& 0x80) != 0 do
          bxor(crc <<< 1, 0x07)
        else
          crc <<< 1
        end
        |> band(0xFF)
      end)
    end
    |> List.to_tuple()
  )

  @doc """
  Calculate CRC using the specified algorithm.

  ## Supported Algorithms

  - `:crc32` - CRC-32 (uses Erlang built-in, polynomial 0x04C11DB7)
  - `:crc16_ccitt` - CRC-16-CCITT (polynomial 0x1021, init 0xFFFF)
  - `:crc16_xmodem` - CRC-16-XMODEM (polynomial 0x1021, init 0x0000)
  - `:crc8` - CRC-8 (polynomial 0x07, init 0x00)
  - `:xor_checksum` - Simple XOR of all bytes

  ## Examples

      iex> CRC.calculate(:crc32, "123456789")
      0xCBF43926

      iex> CRC.calculate(:crc16_ccitt, "123456789")
      0x29B1

      iex> CRC.calculate(:xor_checksum, <<0x01, 0x02, 0x03>>)
      0x00
  """
  @spec calculate(atom(), binary()) :: non_neg_integer()
  def calculate(:crc32, data) when is_binary(data) do
    :erlang.crc32(data)
  end

  def calculate(:crc16_ccitt, data) when is_binary(data) do
    crc16_ccitt(data, 0xFFFF)
  end

  def calculate(:crc16_xmodem, data) when is_binary(data) do
    crc16_xmodem(data, 0x0000)
  end

  def calculate(:crc8, data) when is_binary(data) do
    crc8(data, 0x00)
  end

  def calculate(:xor_checksum, data) when is_binary(data) do
    xor_checksum(data)
  end

  def calculate(algorithm, _data) do
    raise ArgumentError, "Unknown CRC algorithm: #{inspect(algorithm)}"
  end

  @doc """
  Returns the size in bytes for a CRC algorithm.
  """
  @spec size(atom()) :: pos_integer()
  def size(:crc32), do: 4
  def size(:crc16_ccitt), do: 2
  def size(:crc16_xmodem), do: 2
  def size(:crc8), do: 1
  def size(:xor_checksum), do: 1
  def size(algorithm), do: raise(ArgumentError, "Unknown CRC algorithm: #{inspect(algorithm)}")

  @doc """
  Encode a CRC value as binary with specified endianness.
  """
  @spec encode(non_neg_integer(), atom(), :big | :little) :: binary()
  def encode(crc, algorithm, endian \\ :big) do
    case {size(algorithm), endian} do
      {1, _} -> <<crc::8>>
      {2, :big} -> <<crc::16-big>>
      {2, :little} -> <<crc::16-little>>
      {4, :big} -> <<crc::32-big>>
      {4, :little} -> <<crc::32-little>>
    end
  end

  @doc """
  Decode a CRC value from binary with specified endianness.
  """
  @spec decode(binary(), atom(), :big | :little) :: non_neg_integer()
  def decode(binary, algorithm, endian \\ :big) do
    case {size(algorithm), endian} do
      {1, _} ->
        <<crc::8>> = binary
        crc

      {2, :big} ->
        <<crc::16-big>> = binary
        crc

      {2, :little} ->
        <<crc::16-little>> = binary
        crc

      {4, :big} ->
        <<crc::32-big>> = binary
        crc

      {4, :little} ->
        <<crc::32-little>> = binary
        crc
    end
  end

  @doc """
  Verify a CRC by comparing calculated vs expected value.
  Returns `{:ok, data_without_crc}` or `{:error, {:crc_mismatch, expected, actual}}`.
  """
  @spec verify(binary(), atom(), :big | :little) ::
          {:ok, binary()} | {:error, {:crc_mismatch, non_neg_integer(), non_neg_integer()}}
  def verify(data_with_crc, algorithm, endian \\ :big) do
    crc_size = size(algorithm)
    data_size = byte_size(data_with_crc) - crc_size

    if data_size < 0 do
      {:error, :insufficient_data}
    else
      <<data::binary-size(data_size), crc_bytes::binary-size(crc_size)>> = data_with_crc
      expected_crc = decode(crc_bytes, algorithm, endian)
      actual_crc = calculate(algorithm, data)

      if expected_crc == actual_crc do
        {:ok, data}
      else
        {:error, {:crc_mismatch, expected_crc, actual_crc}}
      end
    end
  end

  ## Private CRC Implementations

  # CRC-16-CCITT using lookup table
  defp crc16_ccitt(<<>>, crc), do: crc

  defp crc16_ccitt(<<byte::8, rest::binary>>, crc) do
    index = bxor(crc >>> 8, byte) &&& 0xFF
    new_crc = bxor(crc <<< 8, elem(@crc16_ccitt_table, index)) &&& 0xFFFF
    crc16_ccitt(rest, new_crc)
  end

  # CRC-16-XMODEM using lookup table (same algorithm, different init)
  defp crc16_xmodem(<<>>, crc), do: crc

  defp crc16_xmodem(<<byte::8, rest::binary>>, crc) do
    index = bxor(crc >>> 8, byte) &&& 0xFF
    new_crc = bxor(crc <<< 8, elem(@crc16_xmodem_table, index)) &&& 0xFFFF
    crc16_xmodem(rest, new_crc)
  end

  # CRC-8 using lookup table
  defp crc8(<<>>, crc), do: crc

  defp crc8(<<byte::8, rest::binary>>, crc) do
    index = bxor(crc, byte)
    new_crc = elem(@crc8_table, index)
    crc8(rest, new_crc)
  end

  # Simple XOR checksum
  defp xor_checksum(data) do
    for <<byte::8 <- data>>, reduce: 0 do
      acc -> bxor(acc, byte)
    end
  end
end
