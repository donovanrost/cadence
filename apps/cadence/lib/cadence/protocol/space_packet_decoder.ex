defmodule Cadence.Protocol.SpacePacketDecoder do
  @moduledoc """
  Cadence adapter over the shared CCSDS Space Packet codec.
  """

  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.Identity
  alias Cadence.Protocol.PacketRecord

  @spec decode(RawEvidence.t()) :: {:ok, PacketRecord.t()} | {:error, term()}
  def decode(%RawEvidence{} = raw_evidence) do
    decode_packet(raw_evidence, raw_evidence.raw)
  end

  @spec decode_packet(RawEvidence.t(), binary(), keyword()) ::
          {:ok, PacketRecord.t()} | {:error, term()}
  def decode_packet(%RawEvidence{} = raw_evidence, raw_packet, opts \\ [])
      when is_binary(raw_packet) and is_list(opts) do
    codec_opts = Keyword.take(opts, [:max_packet_size])

    case Codec.decode(raw_packet, codec_opts) do
      {:ok, packet} -> build_packet_record(raw_evidence, packet, raw_packet, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_packet_record(
         %RawEvidence{} = raw_evidence,
         %SpacePacket{} = packet,
         raw_packet,
         opts
       ) do
    provenance =
      base_provenance(raw_evidence) |> Map.merge(Keyword.get(opts, :provenance, %{}))

    {:ok,
     %PacketRecord{
       packet_id:
         Keyword.get_lazy(opts, :packet_id, fn ->
           Identity.packet_id(raw_evidence.evidence_id, 0, raw_packet)
         end),
       evidence_id: raw_evidence.evidence_id,
       mission_id: raw_evidence.mission_id,
       source_endpoint_ref: raw_evidence.source_endpoint_ref,
       spacecraft_id: raw_evidence.spacecraft_id,
       protocol_family: Keyword.get(opts, :protocol_family, raw_evidence.protocol_family),
       packet_kind: Keyword.get(opts, :packet_kind, :space_packet),
       apid: packet.apid,
       sequence_flags: SpacePacket.sequence_flag_value(packet.sequence_flag),
       sequence_count: packet.sequence_count,
       secondary_header?: packet.secondary_header?,
       packet_data: packet.data,
       source_time: Keyword.get(opts, :source_time, raw_evidence.source_time),
       receipt_time: Keyword.get(opts, :receipt_time, raw_evidence.receipt_time),
       provenance: provenance
     }}
  end

  defp base_provenance(%RawEvidence{} = raw_evidence) do
    %{
      evidence_id: raw_evidence.evidence_id,
      source_endpoint_ref: raw_evidence.source_endpoint_ref,
      source_ref: raw_evidence.source_ref,
      metadata: raw_evidence.metadata
    }
  end
end
