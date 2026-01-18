defmodule Cadence.CCSDS.Downlink.PacketAdapter do
  @moduledoc """
  Adapts decoded PDUs into Cadence telemetry packets.
  """

  require Logger

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Telemetry.Packet
  alias Cadence.Time, as: CadenceTime

  @spec to_packet(PDU.t(), SDUOctets.t(), keyword()) :: {:ok, Packet.t()} | {:error, term()}
  def to_packet(%PDU{type: :space_packet, value: %SpacePacket{} = sp}, sdu, _opts) do
    metadata = build_metadata(sdu)

    # Logger.debug(
    #   "PacketAdapter: APID=#{sp.apid}, target_id=#{inspect(metadata[:target_id])}, scid=#{sdu.scid}, vcid=#{sdu.vcid}, packet_size=#{byte_size(sp.raw)} bytes"
    # )

    case Packet.from_ccsds(sp.raw, metadata) do
      {:ok, packet} -> {:ok, packet}
      {:error, reason} -> {:error, reason}
    end
  end

  def to_packet(_pdu, _sdu, _opts), do: {:error, :unsupported_pdu}

  defp build_metadata(%SDUOctets{} = sdu) do
    %{
      target_id: sdu.meta[:target_id] || "default",
      received_at: sdu.timestamp || CadenceTime.now(),
      stored: false
    }
    |> Map.merge(sdu.meta || %{})
  end
end
