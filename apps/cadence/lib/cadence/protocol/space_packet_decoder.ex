defmodule Cadence.Protocol.SpacePacketDecoder do
  @moduledoc """
  Minimal CCSDS space packet decoder for the first Cadence telemetry slice.
  """

  alias Cadence.Ids
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.PacketRecord

  @primary_header_bytes 6

  @spec decode(RawEvidence.t()) :: {:ok, PacketRecord.t()} | {:error, term()}
  def decode(%RawEvidence{} = raw_evidence) do
    decode_packet(raw_evidence, raw_evidence.raw)
  end

  @spec decode_packet(RawEvidence.t(), binary(), keyword()) ::
          {:ok, PacketRecord.t()} | {:error, term()}
  def decode_packet(%RawEvidence{} = raw_evidence, raw_packet, opts \\ [])
      when is_binary(raw_packet) and is_list(opts) do
    if byte_size(raw_packet) < @primary_header_bytes do
      {:error, {:packet_too_short, byte_size(raw_packet)}}
    else
      do_decode_packet(raw_evidence, raw_packet, opts)
    end
  end

  defp do_decode_packet(%RawEvidence{} = raw_evidence, raw_packet, opts) do
    <<
      version::3,
      _type_flag::1,
      secondary_header_flag::1,
      apid::11,
      sequence_flags::2,
      sequence_count::14,
      packet_length::16,
      rest::binary
    >> = raw_packet

    data_field_length = packet_length + 1
    expected_total_length = @primary_header_bytes + data_field_length
    actual_total_length = byte_size(raw_packet)

    cond do
      version != 0 ->
        {:error, {:unsupported_space_packet_version, version}}

      actual_total_length < expected_total_length ->
        {:error, {:truncated_packet, expected_total_length, actual_total_length}}

      actual_total_length > expected_total_length ->
        {:error, {:trailing_bytes, expected_total_length, actual_total_length}}

      true ->
        packet_data = binary_part(rest, 0, data_field_length)

        provenance =
          base_provenance(raw_evidence) |> Map.merge(Keyword.get(opts, :provenance, %{}))

        {:ok,
         %PacketRecord{
           packet_id: Ids.new("packet"),
           evidence_id: raw_evidence.evidence_id,
           mission_id: raw_evidence.mission_id,
           source_endpoint_ref: raw_evidence.source_endpoint_ref,
           spacecraft_id: raw_evidence.spacecraft_id,
           protocol_family: Keyword.get(opts, :protocol_family, raw_evidence.protocol_family),
           packet_kind: Keyword.get(opts, :packet_kind, :space_packet),
           apid: apid,
           sequence_flags: sequence_flags,
           sequence_count: sequence_count,
           secondary_header?: secondary_header_flag == 1,
           packet_data: packet_data,
           source_time: Keyword.get(opts, :source_time, raw_evidence.source_time),
           receipt_time: Keyword.get(opts, :receipt_time, raw_evidence.receipt_time),
           provenance: provenance
         }}
    end
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
