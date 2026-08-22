defmodule CCSDS.SpacePacket.Sequence do
  @moduledoc """
  Pure helpers for independent modulo-16384 Space Packet counts per APID.
  """

  @maximum_count 0x3FFF

  @spec next(0..0x3FFF) :: 0..0x3FFF
  def next(@maximum_count), do: 0
  def next(count) when is_integer(count) and count >= 0 and count < @maximum_count, do: count + 1

  @spec take(map(), 0..0x7FF) :: {0..0x3FFF, map()}
  def take(counters, apid) when is_map(counters) and is_integer(apid) and apid in 0..0x7FF do
    count = Map.get(counters, apid, 0)
    {count, Map.put(counters, apid, next(count))}
  end
end
