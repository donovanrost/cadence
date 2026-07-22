defmodule Cadence.CCSDS.CFDP.Transaction do
  @moduledoc false

  alias Cadence.CCSDS.CFDP.{PDU, TransactionID}

  @spec id(PDU.t()) :: TransactionID.t()
  def id(%PDU{} = pdu),
    do: TransactionID.new(pdu.source_entity_id, pdu.transaction_sequence_number)

  @spec pdu(map(), PDU.payload(), Cadence.CCSDS.CFDP.direction()) :: PDU.t()
  def pdu(state, payload, direction) do
    %PDU{
      direction: direction,
      transmission_mode: state.transmission_mode,
      crc?: state.crc?,
      large_file?: state.large_file?,
      record_boundaries_preserved?: false,
      source_entity_id: state.transaction_id.source_entity_id,
      transaction_sequence_number: state.transaction_id.sequence_number,
      destination_entity_id: state.destination_entity_id,
      entity_id_octets: Map.get(state, :entity_id_octets),
      sequence_number_octets: Map.get(state, :sequence_number_octets),
      payload: payload
    }
  end

  @spec validate_incoming(PDU.t(), map(), Cadence.CCSDS.CFDP.direction()) ::
          :ok | {:error, term()}
  def validate_incoming(%PDU{} = pdu, state, direction) do
    cond do
      pdu.direction != direction ->
        {:error, {:unexpected_pdu_direction, direction, pdu.direction}}

      pdu.transmission_mode != state.transmission_mode ->
        {:error, {:unexpected_transmission_mode, state.transmission_mode, pdu.transmission_mode}}

      id(pdu) != state.transaction_id ->
        {:error, {:unexpected_transaction, state.transaction_id, id(pdu)}}

      pdu.destination_entity_id != state.destination_entity_id ->
        {:error,
         {:unexpected_destination_entity, state.destination_entity_id, pdu.destination_entity_id}}

      true ->
        :ok
    end
  end
end
