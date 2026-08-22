defmodule Cadence.CCSDS.TestSupport.DeterministicGenerator do
  @moduledoc false

  import Bitwise

  @mask 0xFFFFFFFF

  def seed(value) when is_integer(value) do
    normalized = value &&& @mask

    :rand.seed_s(
      :exsss,
      {normalized + 1, bxor(normalized, 0x9E3779B9) + 1, bxor(normalized, 0x85EBCA6B) + 1}
    )
  end

  def integer(state, minimum, maximum)
      when is_integer(minimum) and is_integer(maximum) and minimum <= maximum do
    {offset, state} = :rand.uniform_s(maximum - minimum + 1, state)
    {minimum + offset - 1, state}
  end

  def boolean(state) do
    {value, state} = integer(state, 0, 1)
    {value == 1, state}
  end

  def member(state, values) when is_list(values) and values != [] do
    {index, state} = integer(state, 0, length(values) - 1)
    {Enum.at(values, index), state}
  end

  def binary(state, 0), do: {<<>>, state}

  def binary(state, octets) when is_integer(octets) and octets > 0 do
    {bytes, state} =
      Enum.map_reduce(1..octets, state, fn _index, state -> integer(state, 0, 255) end)

    {:binary.list_to_bin(bytes), state}
  end
end
