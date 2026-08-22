defmodule Cadence.CCSDS.CFDP.TransactionID do
  @moduledoc """
  Stable CFDP transaction identity: source entity plus source-issued sequence.
  """

  @type t :: %__MODULE__{
          source_entity_id: non_neg_integer(),
          sequence_number: non_neg_integer()
        }

  @enforce_keys [:source_entity_id, :sequence_number]
  defstruct [:source_entity_id, :sequence_number]

  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(source_entity_id, sequence_number)
      when is_integer(source_entity_id) and source_entity_id >= 0 and is_integer(sequence_number) and
             sequence_number >= 0 do
    %__MODULE__{source_entity_id: source_entity_id, sequence_number: sequence_number}
  end
end
