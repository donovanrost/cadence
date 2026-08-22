defmodule CCSDS.SDLP.USLP.Service.Indication do
  @moduledoc """
  USLP receiving-end service indication primitive.
  """

  alias CCSDS.Core.LinkFrame
  alias CCSDS.SDLP.USLP.Service.Request

  @type t :: %__MODULE__{
          service: Request.service(),
          data: binary() | nil,
          frame: LinkFrame.t() | nil,
          physical_channel: binary(),
          scid: 0..65_535 | nil,
          vcid: 0..63 | nil,
          map_id: 0..15 | nil,
          packet_version_number: 0..7 | nil,
          sdu_id: term(),
          qos: :sequence_controlled | :expedited | nil,
          quality: :complete | :partial,
          source_frames: [non_neg_integer() | nil],
          packet_quality_indicator: boolean() | nil,
          mapa_sdu_loss_flag: boolean() | nil,
          vca_sdu_loss_flag: boolean() | nil,
          octet_stream_data_loss_flag: boolean() | nil,
          ocf_sdu_loss_flag: boolean() | nil,
          frame_loss_flag: boolean() | nil,
          in_sdu_loss_flag: boolean() | nil,
          verification_status_code: non_neg_integer() | nil,
          notification_type: term(),
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
    :map_id,
    :packet_version_number,
    :sdu_id,
    :qos,
    :quality,
    :source_frames,
    :packet_quality_indicator,
    :mapa_sdu_loss_flag,
    :vca_sdu_loss_flag,
    :octet_stream_data_loss_flag,
    :ocf_sdu_loss_flag,
    :frame_loss_flag,
    :in_sdu_loss_flag,
    :verification_status_code,
    :notification_type,
    :timestamp,
    meta: %{}
  ]
end
