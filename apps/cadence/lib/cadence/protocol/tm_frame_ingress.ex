defmodule Cadence.Protocol.TMFrameIngress do
  @moduledoc """
  Shared TM transfer-frame ingress processing for direct and runtime-backed paths.
  """

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Protocol.{
    ProtocolAnomaly,
    SpacePacketDecoder,
    TMFramePipeline,
    TransferFrameRecord
  }

  alias Cadence.Protocol.PacketRecord

  @type continuity_key :: {non_neg_integer(), non_neg_integer()}
  @type continuity_state :: %{optional(continuity_key()) => non_neg_integer()}

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
      transfer_frame_records = build_transfer_frame_records(raw_evidence, frame_infos)

      protocol_anomalies =
        build_pipeline_anomalies(raw_evidence, decode_anomalies) ++
          build_continuity_anomalies(raw_evidence, frame_infos, continuity_state)

      {:ok,
       %{
         packet_records: packet_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies
       }, rest, next_pipeline_state, next_continuity_state(frame_infos, continuity_state)}
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
         timestamp: raw_evidence.source_time || raw_evidence.receipt_time
       ]}
    end
  end

  defp build_packet_records(%RawEvidence{} = raw_evidence, sdu_octets) when is_list(sdu_octets) do
    Enum.reduce_while(sdu_octets, {:ok, []}, fn sdu, {:ok, acc} ->
      if sdu.sdu_kind_hint != :space_packet do
        {:halt, {:error, {:unsupported_tm_sdu_kind, sdu.sdu_kind_hint}}}
      else
        case SpacePacketDecoder.decode_packet(raw_evidence, sdu.octets,
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
             ) do
          {:ok, %PacketRecord{} = packet_record} ->
            {:cont, {:ok, acc ++ [packet_record]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    end)
  end

  defp build_transfer_frame_records(%RawEvidence{} = raw_evidence, frame_infos)
       when is_list(frame_infos) do
    Enum.map(frame_infos, fn frame_info ->
      frame = frame_info.frame

      TransferFrameRecord.new(%{
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
        raw_frame_offset_bytes: frame_info.raw_frame_offset_bytes,
        raw_frame_length_bytes: frame_info.raw_frame_length_bytes,
        payload_length_bytes: byte_size(frame.payload_octets),
        first_header_pointer: Map.get(frame.meta, :fhp),
        quality: frame.quality,
        source_time: frame.timestamp || raw_evidence.source_time,
        receipt_time: raw_evidence.receipt_time,
        metadata: %{
          frame_meta: frame.meta,
          ocf_present?: is_binary(frame.ocf) and byte_size(frame.ocf) > 0,
          ocf_length_bytes: if(is_binary(frame.ocf), do: byte_size(frame.ocf), else: 0)
        }
      })
    end)
  end

  defp build_pipeline_anomalies(%RawEvidence{} = raw_evidence, anomalies)
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
        anomaly_kind: anomaly.anomaly_kind,
        scid: Map.get(anomaly, :scid, Map.get(metadata, :scid)),
        vcid: Map.get(anomaly, :vcid, Map.get(metadata, :vcid)),
        map_id: Map.get(anomaly, :map_id, Map.get(metadata, :map_id)),
        frame_seq: Map.get(anomaly, :frame_seq, Map.get(metadata, :vcfc)),
        raw_frame_offset_bytes: Map.get(anomaly, :raw_frame_offset_bytes),
        raw_frame_length_bytes: Map.get(anomaly, :raw_frame_length_bytes),
        recorded_at: raw_evidence.receipt_time,
        metadata: metadata
      })
    end)
  end

  defp build_continuity_anomalies(%RawEvidence{} = raw_evidence, frame_infos, continuity_state)
       when is_list(frame_infos) and is_map(continuity_state) do
    frame_infos
    |> Enum.reduce({continuity_state, []}, fn frame_info, {acc_state, acc} ->
      frame = frame_info.frame
      key = {frame.scid, frame.vcid}

      case Map.fetch(acc_state, key) do
        {:ok, previous_frame_seq} ->
          expected_frame_seq = rem(previous_frame_seq + 1, 256)
          next_state = Map.put(acc_state, key, frame.frame_seq)

          if expected_frame_seq == frame.frame_seq do
            {next_state, acc}
          else
            anomaly =
              ProtocolAnomaly.new(%{
                evidence_id: raw_evidence.evidence_id,
                mission_id: raw_evidence.mission_id,
                source_endpoint_ref: raw_evidence.source_endpoint_ref,
                spacecraft_id: raw_evidence.spacecraft_id,
                protocol_family: raw_evidence.protocol_family,
                direction: raw_evidence.direction,
                anomaly_kind: :frame_sequence_discontinuity,
                scid: frame.scid,
                vcid: frame.vcid,
                map_id: frame.map_id,
                frame_seq: frame.frame_seq,
                raw_frame_offset_bytes: frame_info.raw_frame_offset_bytes,
                raw_frame_length_bytes: frame_info.raw_frame_length_bytes,
                recorded_at: raw_evidence.receipt_time,
                metadata: %{
                  previous_frame_seq: previous_frame_seq,
                  expected_frame_seq: expected_frame_seq,
                  observed_frame_seq: frame.frame_seq
                }
              })

            {next_state, acc ++ [anomaly]}
          end

        :error ->
          {Map.put(acc_state, key, frame.frame_seq), acc}
      end
    end)
    |> elem(1)
  end

  defp next_continuity_state(frame_infos, continuity_state) when is_list(frame_infos) do
    Enum.reduce(frame_infos, continuity_state, fn frame_info, acc ->
      frame = frame_info.frame
      Map.put(acc, {frame.scid, frame.vcid}, frame.frame_seq)
    end)
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

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  end
end
