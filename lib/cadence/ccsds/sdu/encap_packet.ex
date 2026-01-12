defmodule Cadence.CCSDS.SDU.EncapPacket do
  @moduledoc """
  Encapsulation packet representation.
  """

  defstruct [
    :protocol_id,
    :length,
    :user_data,
    :raw
  ]
end
