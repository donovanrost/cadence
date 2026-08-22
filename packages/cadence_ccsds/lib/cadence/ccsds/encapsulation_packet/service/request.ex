defmodule Cadence.CCSDS.EncapsulationPacket.Service.Request do
  @moduledoc """
  Encapsulation Packet service request primitive from CCSDS 133.1-B-3.

  `sdlp_channel` is deliberately opaque: the packet protocol identifies the
  selected data-link channel without taking ownership of link configuration.
  """

  @type t :: %__MODULE__{
          data_unit: binary(),
          sdlp_channel: term(),
          protocol_id: 0..7,
          protocol_id_extension: 0..15 | nil,
          user_defined: 0..15,
          header_octets: 1 | 2 | 4 | 8 | nil,
          meta: map()
        }

  defstruct data_unit: <<>>,
            sdlp_channel: nil,
            protocol_id: nil,
            protocol_id_extension: nil,
            user_defined: 0,
            header_octets: nil,
            meta: %{}
end
