defmodule Cadence.CCSDS.Core.SDUOctets do
  @moduledoc """
  Reassembled SDU octets emitted by SDLP profile services.
  """

  alias Cadence.CCSDS.Core.Types

  @type t :: %__MODULE__{
          profile: Types.profile(),
          scid: Types.scid(),
          vcid: Types.vcid(),
          map_id: Types.map_id(),
          direction: Types.direction(),
          sdu_kind_hint: term(),
          octets: binary(),
          quality: Types.quality(),
          source_frames: [Types.frame_seq()],
          timestamp: Types.timestamp(),
          meta: map()
        }

  defstruct [
    :profile,
    :scid,
    :vcid,
    :map_id,
    :direction,
    :sdu_kind_hint,
    :octets,
    :quality,
    :source_frames,
    :timestamp,
    meta: %{}
  ]
end
