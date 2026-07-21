defmodule Cadence.CCSDS.ChannelCoding.LDPC do
  @moduledoc """
  Systematic CCSDS short-blocklength rate-1/2 LDPC codes.

  The encoder constructs the block-circulant generator matrices specified by
  CCSDS 231.0-B-4 tables 4-1 and 4-2. The binary decoder validates parity and
  can correct one hard-decision bit error while reporting explicit quality
  evidence. Soft-decision belief-propagation remains a receiver-specific
  concern outside this binary codec.
  """

  import Bitwise

  @type code :: :ldpc_128_64 | :ldpc_512_256
  @type quality :: %{
          status: :clean | :corrected,
          corrected_bit: non_neg_integer() | nil
        }

  @seeds_64 [
    0x0E69166BEF4C0BC2,
    0x7766137EBB248418,
    0xC480FEB9CD53A713,
    0x4EAA22FA465EEA11
  ]

  @seeds_256 [
    0x1D21794A22761FAE59945014257E130D74D60540037940142DADEB9CA25EF12E,
    0x60E0B6623C5CE5124D2C81ECC7F469AB20678DBFB7523ECE2B54B906A9DBE98C,
    0xF6739BCF54273E77167BDA120C6C47744C071EFF5E32A7593138670C095C39B5,
    0x28706BD0453002582DAB85F05B9201D08DFDEE2D9D84CA88B371FAE63A4EB07E
  ]

  @spec information_octets(code()) :: pos_integer()
  def information_octets(:ldpc_128_64), do: 8
  def information_octets(:ldpc_512_256), do: 32

  @spec codeword_octets(code()) :: pos_integer()
  def codeword_octets(:ldpc_128_64), do: 16
  def codeword_octets(:ldpc_512_256), do: 64

  @spec encode(binary(), code()) :: {:ok, binary()} | {:error, term()}
  def encode(information, code) when code in [:ldpc_128_64, :ldpc_512_256] do
    information_bits = information_bits(code)

    if bit_size(information) == information_bits do
      information_integer = :binary.decode_unsigned(information)
      parity = parity(information_integer, code)
      {:ok, <<information_integer::size(information_bits), parity::size(information_bits)>>}
    else
      {:error,
       {:invalid_ldpc_information_length, code, byte_size(information), information_octets(code)}}
    end
  end

  @spec decode(binary(), code(), keyword()) ::
          {:ok, binary(), quality()} | {:error, term()}
  def decode(codeword, code, opts \\ []) when code in [:ldpc_128_64, :ldpc_512_256] do
    correction? = Keyword.get(opts, :correct?, true)
    information_bits = information_bits(code)

    if bit_size(codeword) == information_bits * 2 do
      <<information::size(^information_bits), received_parity::size(^information_bits)>> =
        codeword

      syndrome = bxor(parity(information, code), received_parity)
      decode_syndrome(information, received_parity, syndrome, code, correction?)
    else
      {:error, {:invalid_ldpc_codeword_length, code, byte_size(codeword), codeword_octets(code)}}
    end
  end

  @spec valid?(binary(), code()) :: boolean()
  def valid?(codeword, code) do
    case decode(codeword, code, correct?: false) do
      {:ok, _information, %{status: :clean}} -> true
      _other -> false
    end
  end

  defp decode_syndrome(information, _received_parity, 0, code, _correction?) do
    {:ok, encode_information(information, code), quality(:clean, nil)}
  end

  defp decode_syndrome(information, received_parity, syndrome, code, true) do
    case correction_index(syndrome, code) do
      {:information, wire_index} ->
        corrected_information = flip_wire_bit(information, wire_index, information_bits(code))
        validate_correction(corrected_information, received_parity, code, wire_index)

      {:parity, parity_wire_index} ->
        corrected_parity =
          flip_wire_bit(received_parity, parity_wire_index, information_bits(code))

        validate_correction(
          information,
          corrected_parity,
          code,
          information_bits(code) + parity_wire_index
        )

      :uncorrectable ->
        rejected(code, syndrome)
    end
  end

  defp decode_syndrome(_information, _received_parity, syndrome, code, false),
    do: rejected(code, syndrome)

  defp validate_correction(information, parity, code, corrected_bit) do
    if bxor(parity(information, code), parity) == 0 do
      {:ok, encode_information(information, code), quality(:corrected, corrected_bit)}
    else
      rejected(code, bxor(parity(information, code), parity))
    end
  end

  defp correction_index(syndrome, code) do
    cond do
      power_of_two?(syndrome) ->
        {:parity, one_bit_wire_index(syndrome, information_bits(code))}

      information_index = Enum.find(0..(information_bits(code) - 1), &(row(code, &1) == syndrome)) ->
        {:information, information_index}

      true ->
        :uncorrectable
    end
  end

  defp parity(information, code) do
    information_bit_count = information_bits(code)

    Enum.reduce(0..(information_bit_count - 1), 0, fn wire_index, acc ->
      if band(information, 1 <<< (information_bit_count - wire_index - 1)) == 0 do
        acc
      else
        bxor(acc, row(code, wire_index))
      end
    end)
  end

  defp row(code, wire_index) do
    block_size = div(information_bits(code), 4)
    seed = code |> seeds() |> Enum.at(div(wire_index, block_size))
    rotate_right(seed, rem(wire_index, block_size), information_bits(code))
  end

  defp rotate_right(value, 0, _width), do: value

  defp rotate_right(value, shift, width) do
    mask = (1 <<< width) - 1
    band(value >>> shift ||| value <<< (width - shift), mask)
  end

  defp flip_wire_bit(value, wire_index, width),
    do: bxor(value, 1 <<< (width - wire_index - 1))

  defp one_bit_wire_index(value, width) do
    Enum.find(0..(width - 1), &(band(value, 1 <<< (width - &1 - 1)) != 0))
  end

  defp power_of_two?(value) when value > 0, do: band(value, value - 1) == 0

  defp encode_information(information, code) do
    <<information::size(information_bits(code))>>
  end

  defp information_bits(:ldpc_128_64), do: 64
  defp information_bits(:ldpc_512_256), do: 256
  defp seeds(:ldpc_128_64), do: @seeds_64
  defp seeds(:ldpc_512_256), do: @seeds_256
  defp quality(status, corrected_bit), do: %{status: status, corrected_bit: corrected_bit}

  defp rejected(code, syndrome) do
    {:error, {:ldpc_codeword_rejected, %{status: :rejected, code: code, syndrome: syndrome}}}
  end
end
