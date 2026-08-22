defmodule Cadence.CCSDS.ChannelCoding.BCH do
  @moduledoc """
  CCSDS modified (63,56) BCH code with the complemented parity convention.

  Codewords contain seven information octets followed by seven complemented
  parity bits and the required zero filler bit. Decoding supports the standard
  triple-error-detection and single-error-correction operating modes.
  """

  import Bitwise

  @information_octets 7
  @codeword_octets 8
  @generator 0xC5
  @parity_mask 0x7F

  @type decoding_mode :: :detect | :correct
  @type quality :: %{
          status: :clean | :corrected,
          corrected_bit: 0..63 | nil,
          filler_valid?: boolean()
        }

  @spec information_octets() :: pos_integer()
  def information_octets, do: @information_octets

  @spec codeword_octets() :: pos_integer()
  def codeword_octets, do: @codeword_octets

  @spec encode(binary()) :: {:ok, binary()} | {:error, term()}
  def encode(<<information::binary-size(@information_octets)>>) do
    information_integer = :binary.decode_unsigned(information)
    parity = parity(information_integer)
    complemented_parity = bxor(parity, @parity_mask)
    {:ok, <<information::binary, complemented_parity::7, 0::1>>}
  end

  def encode(information) when is_binary(information),
    do: {:error, {:invalid_bch_information_length, byte_size(information)}}

  @spec decode(binary(), decoding_mode()) :: {:ok, binary(), quality()} | {:error, term()}
  def decode(codeword, mode \\ :detect)

  def decode(<<_::binary-size(@codeword_octets)>> = codeword, mode)
      when mode in [:detect, :correct] do
    cond do
      valid?(codeword) ->
        {:ok, information(codeword), quality(:clean, nil, filler_valid?(codeword))}

      mode == :correct ->
        correct(codeword)

      true ->
        {:error, {:bch_codeword_rejected, rejection_evidence(codeword)}}
    end
  end

  def decode(codeword, mode) when is_binary(codeword),
    do: {:error, {:invalid_bch_codeword, byte_size(codeword), mode}}

  @spec valid?(binary()) :: boolean()
  def valid?(<<information::binary-size(@information_octets), parity_octet>>) do
    expected_complemented_parity =
      information
      |> :binary.decode_unsigned()
      |> parity()
      |> bxor(@parity_mask)

    parity_octet >>> 1 == expected_complemented_parity and band(parity_octet, 1) == 0
  end

  def valid?(_codeword), do: false

  defp correct(codeword) do
    candidates =
      0..63
      |> Enum.map(&flip_bit(codeword, &1))
      |> Enum.filter(&valid?/1)

    case candidates do
      [corrected] ->
        corrected_bit = differing_bit(codeword, corrected)

        {:ok, information(corrected), quality(:corrected, corrected_bit, filler_valid?(codeword))}

      _other ->
        {:error, {:bch_codeword_rejected, rejection_evidence(codeword)}}
    end
  end

  defp parity(information_integer) do
    dividend = information_integer <<< 7

    62..7//-1
    |> Enum.reduce(dividend, fn bit_position, remainder ->
      if band(remainder, 1 <<< bit_position) == 0 do
        remainder
      else
        bxor(remainder, @generator <<< (bit_position - 7))
      end
    end)
    |> band(@parity_mask)
  end

  defp information(<<information::binary-size(@information_octets), _parity_octet>>),
    do: information

  defp filler_valid?(<<_::binary-size(@information_octets), parity_octet>>),
    do: band(parity_octet, 1) == 0

  defp flip_bit(codeword, wire_bit_index) do
    integer = :binary.decode_unsigned(codeword)
    <<bxor(integer, 1 <<< (63 - wire_bit_index))::unsigned-big-size(64)>>
  end

  defp differing_bit(left, right) do
    difference = bxor(:binary.decode_unsigned(left), :binary.decode_unsigned(right))
    Enum.find(0..63, &(band(difference, 1 <<< (63 - &1)) != 0))
  end

  defp quality(status, corrected_bit, filler_valid?) do
    %{status: status, corrected_bit: corrected_bit, filler_valid?: filler_valid?}
  end

  defp rejection_evidence(codeword) do
    %{
      status: :rejected,
      corrected_bit: nil,
      filler_valid?: filler_valid?(codeword)
    }
  end
end
