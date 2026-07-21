defmodule Cadence.CCSDS.SDLP.TM.Service.Indication do
  @moduledoc """
  Receiving-end TM Virtual Channel service indication primitive.
  """

  alias Cadence.CCSDS.SDLP.TM.Service.Request

  @type t :: %__MODULE__{
          service: Request.service(),
          data: binary(),
          scid: 0..1023,
          vcid: 0..7,
          packet_version_number: 0..7 | nil,
          quality: :complete | :partial,
          source_frames: [0..255],
          vca_status_fields: 0..0x3FFF | nil,
          vca_sdu_loss_flag: boolean() | nil,
          verification_status_code: non_neg_integer() | nil,
          timestamp: DateTime.t() | nil,
          meta: map()
        }

  defstruct [
    :service,
    :data,
    :scid,
    :vcid,
    :packet_version_number,
    :quality,
    :source_frames,
    :vca_status_fields,
    :vca_sdu_loss_flag,
    :verification_status_code,
    :timestamp,
    meta: %{}
  ]
end
