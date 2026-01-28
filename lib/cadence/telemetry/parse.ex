defmodule Cadence.Telemetry.Parse do
  @moduledoc """
  Parse stage: classify raw bytes into a tagged telemetry unit.
  """

  alias Cadence.Telemetry.{
    EncapPacket,
    Evidence,
    PacketEnvelope,
    ParsedUnit,
    SpacePacket,
    UnknownUnit
  }

  @spec run(PacketEnvelope.t()) ::
          {:ok, ParsedUnit.t(), PacketEnvelope.t()}
          | {:error, ParsedUnit.parse_error(), PacketEnvelope.t()}
  def run(%PacketEnvelope{} = envelope) do
    case SpacePacket.parse(envelope.raw) do
      {:ok, %SpacePacket{} = space_packet} ->
        apid = SpacePacket.get_apid(space_packet)

        envelope =
          envelope
          |> PacketEnvelope.add_evidence(Evidence.apid(apid, :space_packet_header, :high))
          |> PacketEnvelope.add_evidence(Evidence.packet_format(:space_packet, :parse, :high))

        {:ok, {:space_packet, space_packet}, envelope}

      {:error, {:malformed, reason, context}} ->
        {:error, {:malformed, reason, context}, envelope}

      {:error, {:no_match, _reason, _context}} ->
        case EncapPacket.parse(envelope.raw) do
          {:unknown, %UnknownUnit{} = unknown} ->
            {:ok, {:unknown, unknown}, envelope}

          _ ->
            {:ok, {:unknown, %UnknownUnit{reason: :no_match, raw: nil, context: %{}}}, envelope}
        end
    end
  end
end
