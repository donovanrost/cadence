defmodule Cadence.CCSDS.SDU.SpacePacket do
  @moduledoc """
  CCSDS Space Packet representation.
  """

  defstruct [
    :apid,
    :sequence_flags,
    :sequence_count,
    :packet_length,
    :version,
    :type,
    :secondary_header_flag,
    :timestamp,
    :target_hash,
    :user_data,
    :raw
  ]
end
