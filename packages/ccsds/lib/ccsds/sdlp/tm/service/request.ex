defmodule CCSDS.SDLP.TM.Service.Request do
  @moduledoc """
  Sending-end TM Virtual Channel service request primitive.

  Packet requests carry one or more complete, forward-ordered Space Packets.
  VCA requests carry one fixed-length VCA_SDU and its mandatory 14-bit status
  fields; the semantics of those status bits remain user-defined.
  """

  @type service :: :virtual_channel_packet | :virtual_channel_access

  @type t :: %__MODULE__{
          service: service(),
          data: binary(),
          scid: 0..1023,
          vcid: 0..7,
          packet_version_number: 0..7 | nil,
          vca_status_fields: 0..0x3FFF | nil,
          timestamp: DateTime.t() | nil,
          meta: map()
        }

  defstruct [
    :service,
    :data,
    :scid,
    :vcid,
    :packet_version_number,
    :vca_status_fields,
    :timestamp,
    meta: %{}
  ]
end
