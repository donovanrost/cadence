defmodule CCSDS.ChannelCoding.Randomizer do
  @moduledoc """
  CCSDS TC pseudo-randomizer from CCSDS 231.0-B-4 section 6.

  Applying the randomizer twice restores the original octets. Each call starts
  the bit-transition generator in the required all-ones state.
  """

  import Bitwise

  @initial_state List.duplicate(1, 8)

  @spec apply(binary()) :: binary()
  def apply(octets) when is_binary(octets) do
    mask = sequence(byte_size(octets))

    octets
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(mask))
    |> Enum.map(fn {octet, mask_octet} -> bxor(octet, mask_octet) end)
    |> :binary.list_to_bin()
  end

  @spec sequence(non_neg_integer()) :: binary()
  def sequence(octet_count) when is_integer(octet_count) and octet_count >= 0 do
    octet_count
    |> Kernel.*(8)
    |> generate_bits(@initial_state, [])
    |> :erlang.list_to_bitstring()
  end

  defp generate_bits(0, _state, acc), do: Enum.reverse(acc)

  defp generate_bits(remaining, [output | rest] = state, acc) do
    next =
      state
      |> Enum.take(5)
      |> Kernel.++([Enum.at(state, 6)])
      |> Enum.reduce(0, &bxor/2)

    generate_bits(remaining - 1, rest ++ [next], [<<output::1>> | acc])
  end
end
