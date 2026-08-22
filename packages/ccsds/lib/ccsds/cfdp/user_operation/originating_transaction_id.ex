defmodule CCSDS.CFDP.UserOperation.OriginatingTransactionID do
  @moduledoc "Typed Originating Transaction ID reserved message."

  alias CCSDS.CFDP.TransactionID

  @type t :: %__MODULE__{
          transaction_id: TransactionID.t(),
          entity_id_octets: 1..8 | nil,
          sequence_number_octets: 1..8 | nil
        }

  @enforce_keys [:transaction_id]
  defstruct [:transaction_id, :entity_id_octets, :sequence_number_octets]
end
