defmodule Cadence.CCSDS.SDLP.AOS.Service.Request do
  @moduledoc """
  AOS sending-end service request primitive.

  `data` carries Packet, Bitstream, VCA, OCF, or Insert service data. `frame`
  carries the complete AOS Transfer Frame used by VCF and MCF services.
  """

  alias Cadence.CCSDS.Core.LinkFrame

  @type service ::
          :virtual_channel_packet
          | :bitstream
          | :virtual_channel_access
          | :virtual_channel_operational_control
          | :virtual_channel_frame
          | :master_channel_frame
          | :insert

  @type t :: %__MODULE__{
          service: service(),
          data: binary() | nil,
          frame: LinkFrame.t() | binary() | nil,
          physical_channel: binary() | nil,
          scid: 0..1023 | nil,
          vcid: 0..63 | nil,
          packet_version_number: 0..7 | nil,
          valid_bits: pos_integer() | nil,
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
    :valid_bits,
    :timestamp,
    meta: %{}
  ]
end
