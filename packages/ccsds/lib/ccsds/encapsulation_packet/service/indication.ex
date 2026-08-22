defmodule CCSDS.EncapsulationPacket.Service.Indication do
  @moduledoc """
  Encapsulation Packet service indication delivered to a protocol user.
  """

  @type t :: %__MODULE__{
          data_unit: binary(),
          sdlp_channel: term(),
          protocol_id: 0..7,
          protocol_id_extension: 0..15 | nil,
          user_defined: 0..15,
          header_octets: 1 | 2 | 4 | 8,
          meta: map()
        }

  defstruct [
    :data_unit,
    :sdlp_channel,
    :protocol_id,
    :protocol_id_extension,
    :user_defined,
    :header_octets,
    meta: %{}
  ]
end
