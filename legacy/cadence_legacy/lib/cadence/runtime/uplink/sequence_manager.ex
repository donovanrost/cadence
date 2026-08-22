defmodule Cadence.Runtime.Uplink.SequenceManager do
  @moduledoc """
  Sequence counter management for uplink SpacePacket PDUs.
  """

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket

  @sequence_mod 16_384

  @spec prepare_pdu(PDU.t(), map()) :: {:ok, PDU.t(), map()} | {:error, term()}
  def prepare_pdu(%PDU{type: :space_packet, value: %SpacePacket{} = packet} = pdu, counts) do
    if is_nil(packet.apid) do
      {:error, :missing_apid}
    else
      {sequence_count, next_counts} =
        if is_nil(packet.sequence_count) do
          next_sequence(counts, packet.apid)
        else
          {packet.sequence_count, counts}
        end

      updated_packet =
        packet
        |> ensure_sequence_flags()
        |> Map.put(:sequence_count, sequence_count)

      {:ok, %{pdu | value: updated_packet}, next_counts}
    end
  end

  def prepare_pdu(%PDU{} = pdu, counts), do: {:ok, pdu, counts}

  defp next_sequence(counts, apid) do
    current = Map.get(counts, apid, -1)
    next = rem(current + 1, @sequence_mod)
    {next, Map.put(counts, apid, next)}
  end

  defp ensure_sequence_flags(%SpacePacket{sequence_flags: nil} = packet) do
    %{packet | sequence_flags: 3}
  end

  defp ensure_sequence_flags(packet), do: packet
end
