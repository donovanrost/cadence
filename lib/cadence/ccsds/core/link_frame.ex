defmodule Cadence.CCSDS.Core.LinkFrame do
  @moduledoc """
  Semantic representation of a TM/AOS/USLP transfer frame.
  """

  alias Cadence.CCSDS.Core.Types

  @type t :: %__MODULE__{
          profile: Types.profile(),
          scid: Types.scid(),
          vcid: Types.vcid(),
          map_id: Types.map_id(),
          frame_seq: Types.frame_seq(),
          payload_octets: binary(),
          quality: Types.quality(),
          ocf: binary() | nil,
          timestamp: Types.timestamp(),
          meta: map()
        }

  defstruct [
    :profile,
    :scid,
    :vcid,
    :map_id,
    :frame_seq,
    :payload_octets,
    :quality,
    :ocf,
    :timestamp,
    meta: %{}
  ]
end
