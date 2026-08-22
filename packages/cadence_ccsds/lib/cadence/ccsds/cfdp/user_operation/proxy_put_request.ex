defmodule Cadence.CCSDS.CFDP.UserOperation.ProxyPutRequest do
  @moduledoc "Typed Proxy Put Request reserved message."

  @type t :: %__MODULE__{
          destination_entity_id: non_neg_integer(),
          destination_entity_id_octets: 1..8 | nil,
          source_file_name: binary(),
          destination_file_name: binary()
        }

  @enforce_keys [:destination_entity_id]
  defstruct [
    :destination_entity_id,
    :destination_entity_id_octets,
    source_file_name: <<>>,
    destination_file_name: <<>>
  ]
end
