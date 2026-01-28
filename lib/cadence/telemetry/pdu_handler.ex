defmodule Cadence.Telemetry.PDUHandler do
  @moduledoc """
  Telemetry handler that converts space packet PDUs into telemetry events.
  """

  @behaviour Cadence.CCSDS.PDUHandler

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Telemetry.{Evidence, PacketEnvelope}
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
    with %SDUOctets{} = sdu <- Map.get(ctx, :sdu),
         {:ok, raw} <- raw_from_pdu(pdu, sdu) do
      metadata = Map.get(ctx, :base_meta, %{})
      envelope = build_envelope(raw, pdu, sdu, ctx, metadata)
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

  defp build_envelope(raw, %PDU{} = pdu, %SDUOctets{} = sdu, ctx, metadata) do
    provenance =
      %{}
      |> maybe_put(:interface_id, Map.get(ctx, :interface_id) || metadata[:interface_id])
      |> maybe_put(:source, metadata[:source])
      |> maybe_put(:link_key, metadata[:link_key])
      |> maybe_put(:channel_key, metadata[:channel_key])
      |> maybe_put(:source_frames, sdu.source_frames || metadata[:source_frames])

    evidence =
      []
      |> maybe_add(Evidence.scid(sdu.scid, :link, :high))
      |> maybe_add(Evidence.vcid(sdu.vcid, :link, :high))
      |> maybe_add(Evidence.map_id(sdu.map_id, :link, :high))
      |> maybe_add(Evidence.interface_id(Map.get(ctx, :interface_id), :ingest, :high))
      |> maybe_add(Evidence.apid(pdu_apid(pdu), :space_packet_header, :high))
      |> maybe_add(Evidence.target_hint(metadata[:target_id], :ingest, :low))

    PacketEnvelope.new(Map.get(ctx, :mission_id) || metadata[:mission_id], raw,
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_add(list, %Evidence{value: nil}), do: list
  defp maybe_add(list, %Evidence{} = evidence), do: list ++ [evidence]
end
