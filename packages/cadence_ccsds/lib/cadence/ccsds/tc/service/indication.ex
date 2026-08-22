defmodule Cadence.CCSDS.TC.Service.Indication do
  @moduledoc """
  Receiving-end TC data-service indication primitive.
  """

  alias Cadence.CCSDS.TC.Service.{Configuration, Request}

  @type t :: %__MODULE__{
          service: Configuration.service(),
          data: binary() | Cadence.CCSDS.Core.LinkFrame.t(),
          scid: 0..1023,
          vcid: 0..63 | nil,
          map_id: 0..63 | nil,
          packet_version_number: 0..7 | nil,
          service_type: Request.service_type(),
          quality: :complete | :partial,
          source_frames: [0..255],
          timestamp: DateTime.t() | nil,
          verification_status_code: non_neg_integer() | nil,
          meta: map()
        }

  defstruct [
    :service,
    :data,
    :scid,
    :vcid,
    :map_id,
    :packet_version_number,
    :service_type,
    :quality,
    :source_frames,
    :timestamp,
    :verification_status_code,
    meta: %{}
  ]
end
