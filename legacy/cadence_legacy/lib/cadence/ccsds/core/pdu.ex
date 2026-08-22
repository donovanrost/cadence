defmodule Cadence.CCSDS.Core.PDU do
  @moduledoc """
  Typed payload produced by SDU decoding.
  """

  alias Cadence.CCSDS.Core.Types

  @type pdu_type :: :space_packet | :encap | {:custom, String.t(), pos_integer()}

  @type t :: %__MODULE__{
          type: pdu_type(),
          value: term(),
          quality: Types.quality(),
          timestamp: Types.timestamp(),
          meta: map()
        }

  defstruct [
    :type,
    :value,
    :quality,
    :timestamp,
    meta: %{}
  ]
end
