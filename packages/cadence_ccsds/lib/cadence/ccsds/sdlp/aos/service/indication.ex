defmodule Cadence.CCSDS.SDLP.AOS.Service.Indication do
  @moduledoc """
  AOS receiving-end service indication primitive.
  """

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.AOS.Service.Request

  @type t :: %__MODULE__{
          service: Request.service(),
          data: binary() | nil,
          frame: LinkFrame.t() | nil,
          physical_channel: binary(),
          scid: 0..1023 | nil,
          vcid: 0..63 | nil,
          packet_version_number: 0..7 | nil,
          quality: :complete | :partial,
          source_frames: [0..0xFFFFFF],
          valid_bits: non_neg_integer() | nil,
          bitstream_data_loss_flag: boolean() | nil,
          vca_sdu_loss_flag: boolean() | nil,
          ocf_sdu_loss_flag: boolean() | nil,
          frame_loss_flag: boolean() | nil,
          in_sdu_loss_flag: boolean() | nil,
          verification_status_code: non_neg_integer() | nil,
          timestamp: DateTime.t() | nil,
          meta: map()
        }

  defstruct [
    :service,
    :data,
    :frame,
    :physical_channel,
    :scid,
    :vcid,
    :packet_version_number,
    :quality,
    :source_frames,
    :valid_bits,
    :bitstream_data_loss_flag,
    :vca_sdu_loss_flag,
    :ocf_sdu_loss_flag,
    :frame_loss_flag,
    :in_sdu_loss_flag,
    :verification_status_code,
    :timestamp,
    meta: %{}
  ]
end
