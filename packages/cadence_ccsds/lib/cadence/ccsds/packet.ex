defmodule Cadence.CCSDS.Packet do
  @moduledoc """
  Common namespace for CCSDS packet-protocol service mechanics.

  `Cadence.CCSDS.SpacePacket` and `Cadence.CCSDS.EncapsulationPacket` are
  sibling packet protocols identified by Packet Version Numbers zero and seven,
  respectively. Their protocol-specific value types and codecs retain those
  standard names; shared format detection and packet-block configuration live
  under this namespace.
  """

  alias Cadence.CCSDS.{EncapsulationPacket, SpacePacket}

  @type packet_version_number :: 0..7
  @type t :: SpacePacket.t() | EncapsulationPacket.t()
end
