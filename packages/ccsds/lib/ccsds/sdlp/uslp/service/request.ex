defmodule CCSDS.SDLP.USLP.Service.Request do
  @moduledoc """
  USLP sending-end service request primitive.

  The service names correspond to the ten data-transfer and management
  services in CCSDS 732.1-B-3. COP directives are represented without binding
  this data-link service boundary to a particular COP-1 or COP-P engine.
  """

  alias CCSDS.Core.LinkFrame

  @type service ::
          :map_packet
          | :virtual_channel_packet
          | :map_access
          | :virtual_channel_access
          | :map_octet_stream
          | :master_channel_operational_control
          | :virtual_channel_frame
          | :master_channel_frame
          | :insert
          | :cops_management

  @type t :: %__MODULE__{
          service: service(),
          data: binary() | nil,
          frame: LinkFrame.t() | binary() | nil,
          physical_channel: binary() | nil,
          scid: 0..65_535 | nil,
          vcid: 0..63 | nil,
          map_id: 0..15 | nil,
          packet_version_number: 0..7 | nil,
          sdu_id: term(),
          qos: :sequence_controlled | :expedited | nil,
          repetitions: non_neg_integer() | nil,
          directive: term(),
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
    :repetitions,
    :directive,
    :timestamp,
    meta: %{}
  ]
end
