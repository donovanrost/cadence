defmodule Cadence.CCSDS.Core.TransportUnit do
  @moduledoc """
  Transport-managed wrapper around a PDU.
  """

  alias Cadence.CCSDS.Core.{PDU, Types}

  @type t :: %__MODULE__{
          pdu: PDU.t(),
          state: term(),
          quality: Types.quality(),
          timestamp: Types.timestamp(),
          meta: map()
        }

  defstruct [
    :pdu,
    :state,
    :quality,
    :timestamp,
    meta: %{}
  ]
end
