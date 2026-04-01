defmodule Cadence.Telemetry.PDUHandler do
  @moduledoc """
  Telemetry handler that converts space packet PDUs into telemetry events.
  """

  @behaviour Cadence.CCSDS.PDUHandler

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Telemetry.{Evidence, MetricsConfig, PacketEnvelope, PipelineMetrics}
  alias Cadence.Time, as: CadenceTime

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def accepts?(%PDU{type: :space_packet, value: %SpacePacket{apid: apid}}, ctx)
      when is_integer(apid) do
    not cop1_report_apid?(ctx, apid)
  end

  def accepts?(%PDU{type: :space_packet}, _ctx), do: true
  def accepts?(_pdu, _ctx), do: false

  @impl true
  def handle_pdu(%PDU{} = pdu, ctx, state) do
    start_ns =
      if MetricsConfig.timing_sample?(),
        do: CadenceTime.monotonic(:nanosecond),
        else: nil

    mission_id = Map.get(ctx, :mission_id) || get_in(ctx, [:base_meta, :mission_id])

    metric_refs =
      Map.get(ctx, :metrics_refs) ||
        PipelineMetrics.partition_refs(mission_id, PipelineMetrics.ingress_partition())

    with %SDUOctets{} = sdu <- Map.get(ctx, :sdu),
         {:ok, raw} <- raw_from_pdu(pdu, sdu) do
      metadata = Map.get(ctx, :base_meta, %{})
      envelope = build_envelope(mission_id, raw, pdu, sdu, ctx, metadata)

      if mission_id do
        if is_integer(start_ns) do
          duration_us = div(CadenceTime.monotonic(:nanosecond) - start_ns, 1000)

          PipelineMetrics.record_timing_refs(metric_refs, :envelope_build, duration_us)
        end

        PipelineMetrics.inc_refs(metric_refs, :envelopes_emitted)
      end

      {:ok, [envelope], state}
    else
      nil -> {:error, :missing_sdu, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp cop1_report_apid?(ctx, apid) do
    case Map.get(ctx, :cop1_report_apids) do
      %MapSet{} = apids -> MapSet.member?(apids, apid)
      apids when is_list(apids) -> Enum.member?(apids, apid)
      _ -> false
    end
  end

  defp raw_from_pdu(%PDU{value: %SpacePacket{raw: raw}}, _sdu) when is_binary(raw) do
    {:ok, raw}
  end

  defp raw_from_pdu(_pdu, %SDUOctets{octets: octets}) when is_binary(octets) do
    {:ok, octets}
  end

  defp raw_from_pdu(_pdu, _sdu), do: {:error, :missing_raw}

  defp build_envelope(mission_id, raw, %PDU{} = pdu, %SDUOctets{} = sdu, ctx, metadata) do
    transport_id = Map.get(ctx, :transport_id)
    source_frames = sdu.source_frames || metadata[:source_frames]

    provenance =
      build_provenance(
        transport_id || metadata[:transport_id],
        metadata[:source],
        metadata[:link_key],
        metadata[:channel_key],
        source_frames
      )

    evidence =
      build_evidence(
        sdu.scid,
        sdu.vcid,
        sdu.map_id,
        transport_id,
        pdu_apid(pdu),
        metadata[:target_id]
      )

    PacketEnvelope.new(mission_id || metadata[:mission_id], raw,
      ingest_ts: metadata[:received_at] || CadenceTime.now(),
      ingest_monotonic_ns: metadata[:ingest_monotonic_ns] || CadenceTime.monotonic(:nanosecond),
      provenance: provenance,
      evidence: evidence,
      config_version_seen: Map.get(ctx, :config_version, 0),
      mode: metadata[:mode] || :realtime,
      quality: pdu.quality
    )
  end

  defp pdu_apid(%PDU{value: %SpacePacket{apid: apid}}), do: apid
  defp pdu_apid(_pdu), do: nil

  defp build_provenance(transport_id, source, link_key, channel_key, source_frames) do
    []
    |> maybe_prepend_entry(:transport_id, transport_id)
    |> maybe_prepend_entry(:source, source)
    |> maybe_prepend_entry(:link_key, link_key)
    |> maybe_prepend_entry(:channel_key, channel_key)
    |> maybe_prepend_entry(:source_frames, source_frames)
    |> provenance_map()
  end

  defp build_evidence(scid, vcid, map_id, transport_id, apid, target_hint) do
    []
    |> maybe_prepend_evidence(:scid, scid, :link, :high)
    |> maybe_prepend_evidence(:vcid, vcid, :link, :high)
    |> maybe_prepend_evidence(:map_id, map_id, :link, :high)
    |> maybe_prepend_evidence(:transport_id, transport_id, :ingest, :high)
    |> maybe_prepend_evidence(:apid, apid, :space_packet_header, :high)
    |> maybe_prepend_evidence(:target_hint, target_hint, :ingest, :low)
    |> :lists.reverse()
  end

  defp maybe_prepend_entry(entries, _key, nil), do: entries
  defp maybe_prepend_entry(entries, key, value), do: [{key, value} | entries]

  defp provenance_map([]), do: %{}
  defp provenance_map(entries), do: entries |> :lists.reverse() |> Map.new()

  defp maybe_prepend_evidence(evidence, _kind, nil, _source, _confidence), do: evidence

  defp maybe_prepend_evidence(evidence, kind, value, source, confidence) do
    [%Evidence{kind: kind, value: value, source: source, confidence: confidence} | evidence]
  end
end
