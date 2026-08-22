defmodule Cadence.CFDP.TransactionEvent do
  @moduledoc "JSON-safe protocol event emitted by the CFDP managed runtime adapter."

  alias CCSDS.CFDP.Indication

  @type t :: %__MODULE__{
          event_type: Indication.kind(),
          source_entity_id: non_neg_integer(),
          transaction_sequence_number: non_neg_integer(),
          details: map()
        }

  @enforce_keys [
    :event_type,
    :source_entity_id,
    :transaction_sequence_number,
    :details
  ]

  defstruct [:event_type, :source_entity_id, :transaction_sequence_number, :details]

  @spec from_indication(Indication.t()) :: t()
  def from_indication(%Indication{} = indication) do
    %__MODULE__{
      event_type: indication.type,
      source_entity_id: indication.transaction_id.source_entity_id,
      transaction_sequence_number: indication.transaction_id.sequence_number,
      details: sanitize_details(indication.details)
    }
  end

  defp sanitize_details(details) do
    case Map.pop(details, :file) do
      {file, remaining} when is_binary(file) ->
        Map.put(remaining, :received_file_octets, byte_size(file))

      {_other, remaining} ->
        remaining
    end
  end
end
