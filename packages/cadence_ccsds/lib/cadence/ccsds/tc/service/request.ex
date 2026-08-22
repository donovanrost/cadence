defmodule Cadence.CCSDS.TC.Service.Request do
  @moduledoc """
  Sending-end TC data-service request primitive.

  `:packet_version_number` is required for Packet Services. `:service_type` is
  required for Packet and Access Services and is intentionally absent for
  Frame Services, which provide no Sequence-Controlled or Expedited guarantee.
  """

  alias Cadence.CCSDS.TC.Service.Configuration

  @type service_type :: :sequence_controlled | :expedited | nil

  @type t :: %__MODULE__{
          service: Configuration.service(),
          data: binary() | Cadence.CCSDS.Core.LinkFrame.t(),
          scid: 0..1023,
          vcid: 0..63 | nil,
          map_id: 0..63 | nil,
          packet_version_number: 0..7 | nil,
          sdu_id: term(),
          service_type: service_type(),
          timestamp: DateTime.t() | nil,
          meta: map()
        }

  defstruct [
    :service,
    :data,
    :scid,
    :vcid,
    :map_id,
    :packet_version_number,
    :sdu_id,
    :service_type,
    :timestamp,
    meta: %{}
  ]
end
