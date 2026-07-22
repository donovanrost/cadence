defmodule Cadence.CCSDS.CFDP.Checksum do
  @moduledoc """
  CFDP file checksum procedures.

  The modular checksum can be accumulated from segments in any order by using
  their file offsets. This is distinct from the optional PDU CRC, which is
  handled by the PDU codec.
  """

  import Bitwise

  @modulus 0x1_0000_0000

  @spec compute(0..15, binary(), keyword()) :: {:ok, 0..0xFFFFFFFF} | {:error, term()}
  def compute(type, file, opts \\ [])

  def compute(0, file, _opts) when is_binary(file), do: {:ok, modular(file)}
  def compute(15, file, _opts) when is_binary(file), do: {:ok, 0}

  def compute(type, file, opts) when type in 1..14 and is_binary(file) do
    case Keyword.get(opts, :provider) do
      provider when is_atom(provider) and not is_nil(provider) -> provider.compute(type, file)
      _other -> {:error, {:unsupported_checksum_type, type}}
    end
  end

  def compute(type, file, _opts), do: {:error, {:invalid_checksum_request, type, file}}

  @spec modular(binary(), non_neg_integer()) :: 0..0xFFFFFFFF
  def modular(data, offset \\ 0)

  def modular(data, offset) when is_binary(data) and is_integer(offset) and offset >= 0 do
    leading = rem(offset, 4)
    padded = :binary.copy(<<0>>, leading) <> data
    trailing = rem(4 - rem(byte_size(padded), 4), 4)

    padded
    |> Kernel.<>(:binary.copy(<<0>>, trailing))
    |> sum_words(0)
  end

  @spec update_modular(0..0xFFFFFFFF, non_neg_integer(), binary()) :: 0..0xFFFFFFFF
  def update_modular(checksum, offset, data)
      when is_integer(checksum) and checksum >= 0 and checksum <= 0xFFFFFFFF and
             is_integer(offset) and offset >= 0 and is_binary(data) do
    rem(checksum + modular(data, offset), @modulus)
  end

  defp sum_words(<<>>, sum), do: sum

  defp sum_words(<<word::32, rest::binary>>, sum) do
    sum_words(rest, sum + word &&& 0xFFFFFFFF)
  end
end
