defmodule Cadence.CCSDS.SDLP.USLP.OnlyIdleData do
  @moduledoc """
  Continuous USLP Only Idle Data sequence from CCSDS 732.1-B-3 annex H.

  The Fibonacci-form 32-cell LFSR uses polynomial
  `D^0 + D^1 + D^2 + D^22 + D^32`, starts once in the all-ones state, and is
  deliberately not restarted between OID frames on one physical channel.
  """

  import Bitwise

  @initial_state 0xFFFFFFFF
  @mask 0xFFFFFFFF

  @spec initial_state() :: 0..0xFFFFFFFF
  def initial_state, do: @initial_state

  @spec take(non_neg_integer(), 0..0xFFFFFFFF) :: {binary(), 0..0xFFFFFFFF}
  def take(length, state \\ @initial_state)

  def take(length, state)
      when is_integer(length) and length >= 0 and is_integer(state) and state in 0..@mask do
    Enum.map_reduce(1..length//1, state, fn _index, current -> next_octet(current) end)
    |> then(fn {octets, next_state} -> {:erlang.list_to_binary(octets), next_state} end)
  end

  @spec validate(binary(), 0..0xFFFFFFFF) :: {:ok, 0..0xFFFFFFFF} | {:error, term()}
  def validate(data, state \\ @initial_state) when is_binary(data) do
    {expected, next_state} = take(byte_size(data), state)

    if data == expected,
      do: {:ok, next_state},
      else: {:error, {:invalid_uslp_only_idle_data, first_difference(data, expected)}}
  end

  defp next_octet(state) do
    Enum.reduce(1..8, {0, state}, fn _bit, {octet, current} ->
      {output, next_state} = next_bit(current)
      {octet <<< 1 ||| output, next_state}
    end)
  end

  defp next_bit(state) do
    output = bit(state, 31)
    feedback = bxor(bxor(output, bit(state, 21)), bxor(bit(state, 1), bit(state, 0)))
    {output, (state <<< 1 ||| feedback) &&& @mask}
  end

  defp bit(state, position), do: state >>> position &&& 1

  defp first_difference(actual, expected) do
    actual
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(expected))
    |> Enum.find_index(fn {left, right} -> left != right end)
  end
end
