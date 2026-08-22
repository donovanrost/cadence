defmodule CCSDS.SDLS.AntiReplay do
  @moduledoc """
  Pure SDLS anti-replay sequence transitions.

  Rollover is intentionally rejected because CCSDS 355.0-B-2 leaves rollover
  interpretation to the mission.
  """

  import Bitwise

  @spec next(non_neg_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :sequence_number_rollover}
  def next(current, octets)
      when is_integer(current) and current >= 0 and is_integer(octets) and octets > 0 do
    next = current + 1

    if next < 1 <<< (octets * 8),
      do: {:ok, next},
      else: {:error, :sequence_number_rollover}
  end

  @spec next_binary(binary()) :: {:ok, binary()} | {:error, :sequence_number_rollover}
  def next_binary(value) when is_binary(value) and byte_size(value) > 0 do
    with {:ok, next} <- next(:binary.decode_unsigned(value), byte_size(value)) do
      {:ok, <<next::unsigned-big-integer-size(byte_size(value) * 8)>>}
    end
  end

  @spec verify(non_neg_integer(), non_neg_integer(), pos_integer()) ::
          :ok | {:error, :replayed | :outside_window}
  def verify(received, current, window)
      when is_integer(received) and received >= 0 and is_integer(current) and current >= 0 and
             is_integer(window) and window > 0 do
    cond do
      received <= current -> {:error, :replayed}
      received - current > window -> {:error, :outside_window}
      true -> :ok
    end
  end
end
