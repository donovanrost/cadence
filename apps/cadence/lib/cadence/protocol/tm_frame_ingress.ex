defmodule Cadence.Protocol.TMFrameIngress do
  @moduledoc """
  Shared TM transfer-frame ingress processing for direct and runtime-backed paths.

  Decoder state belongs to one continuous receive stream, not to a partition's
  lifetime. Connection/journal boundaries establish a new counter baseline and
  discard partial data. They cannot establish whether frames were lost while
  this receiver was disconnected. Within a stream, protocol gaps remain anomalies.
  """

  require Logger

  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.Identity
  alias Cadence.Protocol.ScidRoutes

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
          relayed_packet_records: [PacketRecord.t()],
          transfer_frame_records: [TransferFrameRecord.t()],
          protocol_anomalies: [ProtocolAnomaly.t()]
        }

  @spec init() :: {:ok, TMFramePipeline.state()}
  def init do
    TMFramePipeline.init(default_sdu_type: :space_packet)
  end

  @doc """
  Decodes one evidence. `opts[:scid_routes]` is the source endpoint's `Protocol.ScidRoutes` (#1078
  E1b): frames whose SCID is neither the endpoint's own craft's nor a declared relay origin's are
  refused before reassembly (`scid_mismatch`, counted by a telemetry event), and the packets of a
  relayed origin craft come back in `relayed_packet_records`, never in `packet_records`.
  """
  @spec process(RawEvidence.t(), TMFramePipeline.state(), continuity_state(), binary(), keyword()) ::
          {:ok, result(), binary(), TMFramePipeline.state(), continuity_state()}
          | {:error, term(), TMFramePipeline.state(), continuity_state()}
  def process(
        %RawEvidence{} = raw_evidence,
        pipeline_state,
        continuity_state,
        frame_remainder,
        opts \\ []
      )
      when is_map(continuity_state) and is_binary(frame_remainder) and is_list(opts) do
    scid_routes = Keyword.get(opts, :scid_routes)

    with {:ok, codec_opts} <- frame_codec_opts(raw_evidence),
         {:ok, pipeline_state, frame_remainder, next_continuity_state} <-
           prepare_receive_stream(raw_evidence, pipeline_state, continuity_state, frame_remainder),
         absolute_base_offset = absolute_base_offset(raw_evidence, frame_remainder),
         buffer = frame_remainder <> raw_evidence.raw,
         {:ok, sdu_octets, frame_infos, decode_anomalies, rest, next_pipeline_state, scid_check} <-
           TMFramePipeline.decode_sdu_octets_checked(
             buffer,
             codec_opts,
             pipeline_state,
             decode_context(raw_evidence, absolute_base_offset, scid_routes)
           ),
         {:ok, packet_records, relayed_records} <-
           build_packet_records(raw_evidence, sdu_octets, absolute_base_offset, scid_routes) do
      transfer_frame_records =
        build_transfer_frame_records(raw_evidence, frame_infos, absolute_base_offset, buffer)

      protocol_anomalies =
        build_pipeline_anomalies(raw_evidence, decode_anomalies, absolute_base_offset)

      frame_offsets =
        pending_frame_offsets(
          next_continuity_state,
          frame_infos,
          absolute_base_offset,
          next_pipeline_state
        )

      emit_scid_events(raw_evidence, decode_anomalies, relayed_records)

      {:ok,
       %{
         packet_records: packet_records,
         # A relay's packets for another craft (E1b-1: not routed yet, so not processed).
         relayed_packet_records: relayed_records,
         transfer_frame_records: transfer_frame_records,
         protocol_anomalies: protocol_anomalies,
         resume_offset: resume_offset(raw_evidence, rest, frame_offsets),
         # What's still incomplete after this evidence: the partial frame's bytes and the
         # buffered partial packets' octets (given up and counted if the stream ends here).
         incomplete: %{
           frame_bytes: byte_size(rest),
           packet_octets: TMFramePipeline.stats(next_pipeline_state).buffered_octets
         },
         # The frame-SCID cross-check's tally (DECISIONS #102); nil without an expected SCID.
         scid_check: scid_check && Map.put(scid_check, :spacecraft_id, raw_evidence.spacecraft_id)
       }, rest, next_pipeline_state,
       Map.put(next_continuity_state, :pending_frame_offsets, frame_offsets)}
    else
      {:error, reason, next_pipeline_state} ->
        {:error, reason, next_pipeline_state, continuity_state}

      {:error, reason} ->
        {:error, reason, pipeline_state, continuity_state}
    end
  end

  defp prepare_receive_stream(evidence, pipeline, previous, remainder) do
    metadata = evidence.metadata || %{}

    current = %{
      source: {evidence.source_endpoint_ref, evidence.source_ref, evidence.direction},
      journal_stream_id: metadata_value(metadata, :journal_stream_id),
      transport_session_id: metadata_value(metadata, :transport_session_id)
    }

    reason = receive_boundary(previous, current)

    if reason do
      with {:ok, fresh_pipeline} <- init() do
        stats = TMFramePipeline.stats(pipeline)

        Logger.info(
          "TM receive continuity reset: #{reason}; " <>
            "discarded_frame_bytes=#{byte_size(remainder)} " <>
            "discarded_packet_bytes=#{stats.buffered_octets}",
          mission_id: evidence.mission_id,
          source_endpoint_id: evidence.source_endpoint_ref,
          previous_transport_session_id: previous.transport_session_id,
          transport_session_id: current.transport_session_id,
          journal_stream_id: current.journal_stream_id
        )

        {:ok, fresh_pipeline, <<>>, current}
      end
    else
      {:ok, pipeline, remainder,
       Map.put(current, :pending_frame_offsets, Map.get(previous, :pending_frame_offsets, %{}))}
    end
  end

  @doc """
  Where processing of this journal stream may durably resume after this evidence (an absolute
  stream offset): the start of the earliest frame holding bytes of an incomplete frame (the
  remainder) or of an incomplete packet (a reassembly buffer), else the evidence's end. A restart
  that resumes there decodes the partial frame or packet again from its first byte, and nothing
  before it twice (director 11-15: the processing ack ran past them, and they were lost). Nil
  without journal offsets.
  """
  @spec resume_offset(RawEvidence.t(), binary(), map()) :: non_neg_integer() | nil
  def resume_offset(%RawEvidence{} = raw_evidence, rest, frame_offsets) do
    case metadata_value(raw_evidence.metadata || %{}, :journal_end_offset) do
      end_offset when is_integer(end_offset) ->
        Enum.min([end_offset - byte_size(rest) | Map.values(frame_offsets)])

      _no_journal ->
        nil
    end
  end

  # The absolute offsets of the frames a buffered partial packet came from, keyed by
  # {scid, vcid, frame_seq}: this evidence's frames added, then only those a buffer still names.
  defp pending_frame_offsets(continuity, frame_infos, absolute_base_offset, pipeline) do
    known =
      Enum.reduce(frame_infos, Map.get(continuity, :pending_frame_offsets, %{}), fn info, acc ->
        frame = info.frame
        offset = absolute_base_offset + info.raw_frame_offset_bytes
        Map.put(acc, {frame.scid, frame.vcid, frame.frame_seq}, offset)
      end)

    Map.take(known, TMFramePipeline.pending_source_frames(pipeline))
  end

  defp receive_boundary(previous, _current) when map_size(previous) == 0, do: nil

  defp receive_boundary(previous, current) do
    cond do
      previous.source != current.source ->
        :source_changed

      previous.journal_stream_id != current.journal_stream_id ->
        :journal_changed

      previous.transport_session_id != current.transport_session_id ->
        :connection_changed

      true ->
        nil
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

  # Without a source time a frame's time IS its receipt time: each frame takes the receipt time
  # of the journal record its bytes arrived in, not the first record of a merged batch.
  defp decode_context(%RawEvidence{source_time: nil} = raw_evidence, absolute_base_offset, index) do
    raw_evidence
    |> base_context(index)
    |> Map.put(
      :frame_timestamp,
      &RawEvidence.receipt_time_at(raw_evidence, absolute_base_offset + &1)
    )
  end

  defp decode_context(%RawEvidence{} = raw_evidence, _absolute_base_offset, index),
    do: base_context(raw_evidence, index)

  # The pass's one spacecraft's SCID, when the path resolved one (DECISIONS #102): frames with
  # another SCID are refused before reassembly.
  #
  # With the endpoint's relay index (#1078 E1b) the index decides: a relay endpoint accepts its own
  # craft's SCID and its declared origins' (the pass's one spacecraft would refuse them), and an
  # endpoint whose craft has a SCID now refuses the others even when the evidence names none.
  defp base_context(%RawEvidence{} = raw_evidence, index) do
    context = %{direction: raw_evidence.direction, sdu_kind_hint: :space_packet}
    named = metadata_value(raw_evidence.metadata || %{}, :spacecraft_scid)

    cond do
      routed?(index) and (ScidRoutes.relay?(index) or not is_integer(named)) ->
        context
        |> Map.put(:scid_router, &ScidRoutes.classify(index, &1))
        |> Map.put(:expected_scid, index.own_scid)

      is_integer(named) ->
        Map.put(context, :expected_scid, named)

      true ->
        context
    end
  end

  defp routed?(%ScidRoutes{} = index), do: ScidRoutes.checks?(index)
  defp routed?(_none), do: false

  # A packet is received when the frame completing it is: that frame's stamp (receipt fallback).
  defp packet_receipt_time(%RawEvidence{source_time: nil} = raw_evidence, sdu),
    do: sdu.timestamp || raw_evidence.receipt_time

  defp packet_receipt_time(%RawEvidence{} = raw_evidence, _sdu), do: raw_evidence.receipt_time

  defp generation_time_source(%RawEvidence{source_time: nil}), do: :receipt
  defp generation_time_source(%RawEvidence{}), do: :onboard

  defp build_packet_records(
         %RawEvidence{} = raw_evidence,
         sdu_octets,
         absolute_base_offset,
         scid_routes
       )
       when is_list(sdu_octets) do
    sdu_octets
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], []}, fn {sdu, ordinal}, {:ok, direct, relayed} ->
      add_packet_record(
        raw_evidence,
        sdu,
        {ordinal, absolute_base_offset},
        scid_routes,
        {direct, relayed}
      )
    end)
    |> case do
      {:ok, direct, relayed} -> {:ok, Enum.reverse(direct), Enum.reverse(relayed)}
      {:error, reason} -> {:error, reason}
    end
  end

  # One reassembled packet, into the endpoint's own craft's records or (a relay's origin craft's)
  # the relayed ones, which carry that craft and a relayed origin.
  defp add_packet_record(raw_evidence, sdu, position, scid_routes, {direct, relayed}) do
    case route(scid_routes, sdu) do
      {:relayed, craft} ->
        routing = [spacecraft_id: craft, relay: %{via_scid: scid_routes.own_scid}]

        with {:cont, {:ok, relayed}} <-
               reduce_packet_record(raw_evidence, sdu, position, relayed, routing),
             do: {:cont, {:ok, direct, relayed}}

      _direct ->
        with {:cont, {:ok, direct}} <- reduce_packet_record(raw_evidence, sdu, position, direct),
             do: {:cont, {:ok, direct, relayed}}
    end
  end

  # What a reassembled packet's frame was on this endpoint (`ScidRoutes.classify/2`).
  defp route(%ScidRoutes{} = index, sdu) do
    if ScidRoutes.checks?(index) and is_integer(sdu.scid),
      do: ScidRoutes.classify(index, sdu.scid),
      else: :direct
  end

  defp route(_no_index, _sdu), do: :direct

  # The counts a misconfigured SCID shows up in: refused frames, and relayed packets that are
  # decoded but not routed yet (E1b-1).
  defp emit_scid_events(raw_evidence, decode_anomalies, relayed_records) do
    for %{anomaly_kind: kind, scid: scid, metadata: metadata} <- decode_anomalies,
        kind in [:scid_mismatch, :relay_origin_archived] do
      :telemetry.execute(
        [:cadence, :protocol, :scid_check, :refused],
        %{frames: Map.get(metadata, :frames, 1)},
        %{
          mission_id: raw_evidence.mission_id,
          source_endpoint_id: raw_evidence.source_endpoint_ref,
          reason: kind,
          scid: scid,
          expected_scid: Map.get(metadata, :expected_scid)
        }
      )
    end

    relayed_records
    |> Enum.frequencies_by(& &1.spacecraft_id)
    |> Enum.each(fn {craft, count} ->
      :telemetry.execute(
        [:cadence, :protocol, :relay, :not_routed],
        %{packets: count},
        %{
          mission_id: raw_evidence.mission_id,
          source_endpoint_id: raw_evidence.source_endpoint_ref,
          origin_spacecraft_id: craft
        }
      )
    end)
  end

  # `buffer` is the bytes the frames were decoded from (a remainder, then this evidence's), which
  # their offsets index: each frame's own bytes are hashed here, where they are in hand.
  defp build_transfer_frame_records(
         %RawEvidence{} = raw_evidence,
         frame_infos,
         absolute_base_offset,
         buffer
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
        frame_sha256:
          :crypto.hash(
            :sha256,
            binary_part(
              buffer,
              frame_info.raw_frame_offset_bytes,
              frame_info.raw_frame_length_bytes
            )
          ),
        first_header_pointer: Map.get(frame.meta, :fhp),
        quality: frame.quality,
        source_time: frame.timestamp || raw_evidence.source_time,
        receipt_time: RawEvidence.receipt_time_at(raw_evidence, absolute_offset),
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
      metadata = anomaly_metadata(raw_evidence, anomaly)

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

  # A refused frame's anomaly names its contact and path, for a later live read (DECISIONS #102).
  defp anomaly_metadata(raw_evidence, %{anomaly_kind: :scid_mismatch} = anomaly) do
    metadata = raw_evidence.metadata || %{}

    Map.merge(anomaly.metadata, %{
      realized_contact_id: metadata_value(metadata, :realized_contact_id),
      path_id: metadata_value(metadata, :path_id)
    })
  end

  defp anomaly_metadata(_raw_evidence, anomaly), do: Map.get(anomaly, :metadata, %{})

  defp reduce_packet_record(%RawEvidence{} = raw_evidence, sdu, position, acc, routing \\ []) do
    with :ok <- validate_tm_sdu_kind(sdu),
         {:ok, %PacketRecord{} = packet_record} <-
           decode_tm_packet_record(raw_evidence, sdu, position, routing) do
      packet_record = %{packet_record | journal_frame: journal_frame(raw_evidence, sdu, position)}
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

  defp decode_tm_packet_record(%RawEvidence{} = raw_evidence, sdu, position, routing) do
    SpacePacketDecoder.decode_packet(
      raw_evidence,
      sdu.octets,
      routing ++
        [
          packet_id: packet_id(raw_evidence, sdu, position),
          protocol_family: raw_evidence.protocol_family,
          source_time: sdu.timestamp || raw_evidence.source_time,
          receipt_time: packet_receipt_time(raw_evidence, sdu),
          provenance: %{
            generation_time_source: generation_time_source(raw_evidence),
            tm: %{
              scid: sdu.scid,
              vcid: sdu.vcid,
              map_id: sdu.map_id,
              quality: sdu.quality,
              source_frames: sdu.source_frames,
              metadata: Map.drop(sdu.meta, [:raw_frame_offset_bytes, :raw_frame_length_bytes])
            }
          }
        ]
    )
  end

  # A journaled packet's id is its journal position: the stream and the absolute offset of the
  # frame that completed it, with its bytes (#71 follow-up). A replay that batches the journal
  # differently gives it the same id, so it isn't archived twice. Without a journal stream, the
  # evidence-scoped id as before.
  defp packet_id(raw_evidence, sdu, {ordinal, absolute_base_offset}) do
    case {journal_stream_id(raw_evidence), Map.get(sdu.meta || %{}, :raw_frame_offset_bytes)} do
      {stream_id, offset} when is_binary(stream_id) and is_integer(offset) ->
        Identity.journal_packet_id(stream_id, absolute_base_offset + offset, sdu.octets)

      _no_journal_position ->
        Identity.packet_id(raw_evidence.evidence_id, ordinal, sdu.octets)
    end
  end

  # The journal position of the frame that completed the packet (DECISIONS #99): the input of
  # its replay-safe effect ids, `{stream, absolute frame offset, receipt time}`. Batch-independent
  # like journal_packet_id: the receipt time is that of the journal record holding the frame's
  # LAST byte, which is always in this evidence (its first byte may be carried over from earlier
  # evidence, whose records this one doesn't have). nil without a journal position. A struct
  # field, not provenance, so neither the archive entry nor the packet id changes.
  defp journal_frame(raw_evidence, sdu, {_ordinal, absolute_base_offset}) do
    meta = sdu.meta || %{}

    case {journal_stream_id(raw_evidence), Map.get(meta, :raw_frame_offset_bytes),
          Map.get(meta, :raw_frame_length_bytes)} do
      {stream_id, offset, length}
      when is_binary(stream_id) and is_integer(offset) and is_integer(length) and length > 0 ->
        frame_offset = absolute_base_offset + offset
        last_byte = frame_offset + length - 1
        {stream_id, frame_offset, RawEvidence.receipt_time_at(raw_evidence, last_byte)}

      _no_journal_position ->
        nil
    end
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
