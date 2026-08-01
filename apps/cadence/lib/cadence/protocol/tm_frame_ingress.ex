defmodule Cadence.Protocol.TMFrameIngress do
  @moduledoc """
  Shared TM transfer-frame ingress processing for direct and runtime-backed paths.
  """

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.Identity

  alias Cadence.Protocol.{
    ProtocolAnomaly,
    SpacePacketDecoder,
    TMFramePipeline,
    TransferFrameRecord
  }

  alias Cadence.Protocol.PacketRecord

  @type continuity_state :: map()

  @type result :: %{
          packet_records: [PacketRecord.t()],
          transfer_frame_records: [TransferFrameRecord.t()],
          protocol_anomalies: [ProtocolAnomaly.t()]
        }

  @spec init() :: {:ok, TMFramePipeline.state()}
  def init do
    TMFramePipeline.init(default_sdu_type: :space_packet)
  end

  @spec process(RawEvidence.t(), TMFramePipeline.state(), continuity_state(), binary()) ::
          {:ok, result(), binary(), TMFramePipeline.state(), continuity_state()}
          | {:error, term(), TMFramePipeline.state(), continuity_state()}
  def process(%RawEvidence{} = raw_evidence, pipeline_state, continuity_state, frame_remainder)
      when is_map(continuity_state) and is_binary(frame_remainder) do
    with {:ok, codec_opts} <- frame_codec_opts(raw_evidence),
         {:ok, sdu_octets, frame_infos, decode_anomalies, rest, next_pipeline_state} <-
           TMFramePipeline.decode_sdu_octets_detailed(
             frame_remainder <> raw_evidence.raw,
             codec_opts,
             pipeline_state,
             %{
               direction: raw_evidence.direction,
               sdu_kind_hint: :space_packet
             }
           ),
         {:ok, packet_records} <- build_packet_records(raw_evidence, sdu_octets) do
      absolute_base_offset = absolute_base_offset(raw_evidence, frame_remainder)

      transfer_frame_records =
        build_transfer_frame_records(raw_evidence, frame_infos, absolute_base_offset)

      protocol_anomalies =
        build_pipeline_anomalies(raw_evidence, decode_anomalies, absolute_base_offset)

      {:ok,
       %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies
       }, rest, next_pipeline_state, continuity_state}
    else
      {:error, reason, next_pipeline_state} ->
        {:error, reason, next_pipeline_state, continuity_state}

      {:error, reason} ->
        {:error, reason, pipeline_state, continuity_state}
    end
  end

  @spec frame_codec_opts(RawEvidence.t()) :: {:ok, keyword()} | {:error, term()}
  def frame_codec_opts(%RawEvidence{} = raw_evidence) do
    metadata = raw_evidence.metadata || %{}

    with {:ok, frame_size} <- fetch_integer(metadata, :frame_size) do
      {:ok,
       [
         frame_size: frame_size,
         secondary_header_length: fetch_integer(metadata, :secondary_header_length, 0),
         ocf_length: fetch_integer(metadata, :ocf_length, 4),
         fecf: fetch_boolean(metadata, :fecf, false),
         timestamp: raw_evidence.source_time || raw_evidence.receipt_time
       ]}
    end
  end

  defp build_packet_records(%RawEvidence{} = raw_evidence, sdu_octets) when is_list(sdu_octets) do
    sdu_octets
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {sdu, ordinal}, {:ok, acc} ->
      reduce_packet_record(raw_evidence, sdu, ordinal, acc)
    end)
    |> case do
      {:ok, packet_records} -> {:ok, Enum.reverse(packet_records)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_transfer_frame_records(
         %RawEvidence{} = raw_evidence,
         frame_infos,
         absolute_base_offset
       )
       when is_list(frame_infos) do
    Enum.map(frame_infos, fn frame_info ->
      frame = frame_info.frame
      absolute_offset = absolute_base_offset + frame_info.raw_frame_offset_bytes

      TransferFrameRecord.new(%{
        frame_record_id:
          Identity.frame_record_id(
            journal_stream_id(raw_evidence) || raw_evidence.evidence_id,
            absolute_offset,
            frame_info.raw_frame_length_bytes
          ),
        evidence_id: raw_evidence.evidence_id,
        mission_id: raw_evidence.mission_id,
        source_endpoint_ref: raw_evidence.source_endpoint_ref,
        spacecraft_id: raw_evidence.spacecraft_id,
        protocol_family: raw_evidence.protocol_family,
        direction: raw_evidence.direction,
        scid: frame.scid,
        vcid: frame.vcid,
        map_id: frame.map_id,
        frame_seq: frame.frame_seq,
        raw_frame_offset_bytes: absolute_offset,
        raw_frame_length_bytes: frame_info.raw_frame_length_bytes,
        payload_length_bytes: byte_size(frame.payload_octets),
        first_header_pointer: Map.get(frame.meta, :fhp),
        quality: frame.quality,
        source_time: frame.timestamp || raw_evidence.source_time,
        receipt_time: raw_evidence.receipt_time,
        metadata: %{
          frame_meta: frame.meta,
          ocf_present?: is_binary(frame.ocf) and byte_size(frame.ocf) > 0,
          ocf_length_bytes: if(is_binary(frame.ocf), do: byte_size(frame.ocf), else: 0),
          journal_stream_id: journal_stream_id(raw_evidence)
        }
      })
    end)
  end

  defp build_pipeline_anomalies(%RawEvidence{} = raw_evidence, anomalies, absolute_base_offset)
       when is_list(anomalies) do
    Enum.map(anomalies, fn anomaly ->
      metadata = Map.get(anomaly, :metadata, %{})

      ProtocolAnomaly.new(%{
        evidence_id: raw_evidence.evidence_id,
        mission_id: raw_evidence.mission_id,
        source_endpoint_ref: raw_evidence.source_endpoint_ref,
        spacecraft_id: raw_evidence.spacecraft_id,
        protocol_family: raw_evidence.protocol_family,
        direction: raw_evidence.direction,
        anomaly_kind: application_anomaly_kind(anomaly.anomaly_kind),
        scid: Map.get(anomaly, :scid, Map.get(metadata, :scid)),
        vcid: Map.get(anomaly, :vcid, Map.get(metadata, :vcid)),
        map_id: Map.get(anomaly, :map_id, Map.get(metadata, :map_id)),
        frame_seq: Map.get(anomaly, :frame_seq, Map.get(metadata, :vcfc)),
        raw_frame_offset_bytes:
          absolute_offset(Map.get(anomaly, :raw_frame_offset_bytes), absolute_base_offset),
        raw_frame_length_bytes: Map.get(anomaly, :raw_frame_length_bytes),
        recorded_at: raw_evidence.receipt_time,
        metadata: metadata
      })
    end)
  end

  defp reduce_packet_record(%RawEvidence{} = raw_evidence, sdu, ordinal, acc) do
    with :ok <- validate_tm_sdu_kind(sdu),
         {:ok, %PacketRecord{} = packet_record} <-
           decode_tm_packet_record(raw_evidence, sdu, ordinal) do
      {:cont, {:ok, [packet_record | acc]}}
    else
      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp validate_tm_sdu_kind(%{sdu_kind_hint: :space_packet}), do: :ok

  defp validate_tm_sdu_kind(sdu) do
    {:error, {:unsupported_tm_sdu_kind, sdu.sdu_kind_hint}}
  end

  defp decode_tm_packet_record(%RawEvidence{} = raw_evidence, sdu, ordinal) do
    SpacePacketDecoder.decode_packet(raw_evidence, sdu.octets,
      packet_id: Identity.packet_id(raw_evidence.evidence_id, ordinal, sdu.octets),
      protocol_family: raw_evidence.protocol_family,
      source_time: sdu.timestamp || raw_evidence.source_time,
      provenance: %{
        tm: %{
          scid: sdu.scid,
          vcid: sdu.vcid,
          map_id: sdu.map_id,
          quality: sdu.quality,
          source_frames: sdu.source_frames,
          metadata: sdu.meta
        }
      }
    )
  end

  defp application_anomaly_kind(:virtual_channel_frame_count_discontinuity),
    do: :frame_sequence_discontinuity

  defp application_anomaly_kind(kind), do: kind

  defp absolute_base_offset(%RawEvidence{} = raw_evidence, frame_remainder) do
    case metadata_value(raw_evidence.metadata || %{}, :journal_start_offset) do
      offset when is_integer(offset) and offset >= byte_size(frame_remainder) ->
        offset - byte_size(frame_remainder)

      _missing ->
        0
    end
  end

  defp absolute_offset(nil, _base_offset), do: nil
  defp absolute_offset(offset, base_offset) when is_integer(offset), do: base_offset + offset

  defp journal_stream_id(%RawEvidence{} = raw_evidence) do
    metadata_value(raw_evidence.metadata || %{}, :journal_stream_id)
  end

  defp fetch_integer(metadata, key, default \\ :required)

  defp fetch_integer(metadata, key, :required) when is_map(metadata) do
    case metadata_value(metadata, key) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value ->
        {:error, {:missing_tm_metadata, key, value}}
    end
  end

  defp fetch_integer(metadata, key, default) when is_map(metadata) and is_integer(default) do
    case metadata_value(metadata, key) do
      nil -> default
      value when is_integer(value) and value >= 0 -> value
      _value -> default
    end
  end

  defp fetch_boolean(metadata, key, default) when is_map(metadata) and is_boolean(default) do
    case metadata_value(metadata, key) do
      nil -> default
      value when is_boolean(value) -> value
      _value -> default
    end
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    cond do
      Map.has_key?(metadata, key) -> Map.get(metadata, key)
      Map.has_key?(metadata, Atom.to_string(key)) -> Map.get(metadata, Atom.to_string(key))
      true -> nil
    end
  end
end
