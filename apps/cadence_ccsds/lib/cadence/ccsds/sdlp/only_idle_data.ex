defmodule Cadence.CCSDS.SDLP.OnlyIdleData do
  @moduledoc """
  Shared stateful Only Idle Data generator and validator.

  TM and AOS use the same 32-cell Fibonacci LFSR. It is seeded with all ones
  at device start-up and intentionally is not restarted between subsequent
  OID Transfer Frames.
  """

  import Bitwise

  @seed 0xFFFFFFFF

  @type state :: 1..0xFFFFFFFF

  @spec initial_state() :: state()
  def initial_state, do: @seed

  @spec take(non_neg_integer(), state()) :: {binary(), state()}
  def take(length, state \\ @seed)

  def take(0, state) when state in 1..0xFFFFFFFF, do: {<<>>, state}

  def take(length, state)
      when is_integer(length) and length > 0 and state in 1..0xFFFFFFFF do
    generate_bytes(length, state, [])
  end

  @spec validate(binary(), state()) :: {:ok, state()} | {:error, term()}
  def validate(data, state \\ @seed)

  def validate(data, state) when is_binary(data) and state in 1..0xFFFFFFFF do
    {expected, next_state} = take(byte_size(data), state)

    case first_mismatch(data, expected, 0) do
      nil -> {:ok, next_state}
      mismatch -> {:error, {:oid_pn_mismatch, mismatch}}
    end
  end

  def validate(data, state), do: {:error, {:invalid_oid_input, data, state}}

  @spec validate_prefix(binary(), pos_integer(), state()) :: {:ok, state()} | {:error, term()}
  def validate_prefix(data, prefix_octets, state \\ @seed)

  def validate_prefix(data, prefix_octets, state)
      when is_binary(data) and is_integer(prefix_octets) and prefix_octets > 0 and
             state in 1..0xFFFFFFFF do
    compared_octets = min(prefix_octets, byte_size(data))
    {expected, next_state} = take(byte_size(data), state)

    actual_prefix = binary_part(data, 0, compared_octets)
    expected_prefix = binary_part(expected, 0, compared_octets)

    case first_mismatch(actual_prefix, expected_prefix, 0) do
      nil -> {:ok, next_state}
      mismatch -> {:error, {:oid_pn_prefix_mismatch, mismatch}}
    end
  end

  def validate_prefix(data, prefix_octets, state),
    do: {:error, {:invalid_oid_prefix_input, data, prefix_octets, state}}

  defp generate_bytes(0, state, acc),
    do: {acc |> Enum.reverse() |> :binary.list_to_bin(), state}

  defp generate_bytes(remaining, state, acc) do
    {byte, next_state} = generate_byte(state, 0, 0)
    generate_bytes(remaining - 1, next_state, [byte | acc])
  end

  defp generate_byte(state, 8, byte), do: {byte, state}

  defp generate_byte(state, bit_count, byte) do
    {bit, next_state} = next_bit(state)
    generate_byte(next_state, bit_count + 1, byte <<< 1 ||| bit)
  end

  defp next_bit(state) do
    output = state >>> 31 &&& 1

    feedback =
      output
      |> bxor(state >>> 21 &&& 1)
      |> bxor(state >>> 1 &&& 1)
      |> bxor(state &&& 1)

    next_state = (state <<< 1 &&& 0xFFFFFFFF) ||| feedback
    {output, next_state}
  end

  defp first_mismatch(<<>>, <<>>, _offset), do: nil

  defp first_mismatch(
         <<actual, actual_rest::binary>>,
         <<expected, expected_rest::binary>>,
         offset
       ) do
    if actual == expected do
      first_mismatch(actual_rest, expected_rest, offset + 1)
    else
      %{offset: offset, expected: expected, observed: actual}
    end
  end
end
