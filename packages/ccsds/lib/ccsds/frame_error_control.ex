defmodule CCSDS.FrameErrorControl do
  @moduledoc """
  CCSDS Frame Error Control Field generation and validation.

  TM and TC transfer frames use the same 16-bit, MSB-first CRC with generator
  polynomial `x^16 + x^12 + x^5 + 1` and an all-ones initial register. The
  resulting FECF is appended as the final two octets of the transfer frame.
  """

  import Bitwise

  @fecf_size 2
  @initial_register 0xFFFF
  @polynomial 0x1021
  @crc_table (for dividend <- 0..255 do
                Enum.reduce(1..8, dividend <<< 8, fn _bit, register ->
                  shifted = register <<< 1 &&& 0xFFFF

                  if (register &&& 0x8000) == 0,
                    do: shifted,
                    else: bxor(shifted, @polynomial)
                end)
              end)
             |> List.to_tuple()

  @type value :: 0..0xFFFF

  @spec size() :: 2
  def size, do: @fecf_size

  @spec calculate(binary()) :: value()
  def calculate(data) when is_binary(data), do: calculate_bytes(data, @initial_register)

  @spec encode(binary()) :: <<_::16>>
  def encode(data) when is_binary(data), do: <<calculate(data)::16>>

  @spec append(binary()) :: binary()
  def append(frame_without_fecf) when is_binary(frame_without_fecf) do
    frame_without_fecf <> encode(frame_without_fecf)
  end

  @spec validate_and_strip(binary()) ::
          {:ok, frame_without_fecf :: binary(), value()}
          | {:error, :frame_too_short_for_fecf | {:invalid_fecf, value(), value()}}
  def validate_and_strip(frame) when byte_size(frame) < @fecf_size,
    do: {:error, :frame_too_short_for_fecf}

  def validate_and_strip(frame) when is_binary(frame) do
    body_size = byte_size(frame) - @fecf_size
    <<body::binary-size(^body_size), received::16>> = frame
    expected = calculate(body)

    if received == expected do
      {:ok, body, received}
    else
      {:error, {:invalid_fecf, expected, received}}
    end
  end

  defp calculate_bytes(<<>>, register), do: register

  defp calculate_bytes(<<byte, rest::binary>>, register) do
    calculate_bytes(rest, update_byte(byte, register))
  end

  defp update_byte(byte, register) do
    table_index = bxor(register >>> 8, byte)
    bxor(register <<< 8 &&& 0xFFFF, elem(@crc_table, table_index))
  end
end
