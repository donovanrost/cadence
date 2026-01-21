defmodule Cadence.Telemetry.PDUHandler do
  @moduledoc """
  Telemetry handler that converts space packet PDUs into telemetry events.
  """

  @behaviour Cadence.CCSDS.PDUHandler

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Downlink.PacketAdapter
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Events.TelemetryPacket

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
         {:ok, packet} <- PacketAdapter.to_packet(pdu, sdu, Map.get(ctx, :opts, [])) do
      base_meta = Map.get(ctx, :base_meta, %{})
      metadata = Map.merge(base_meta, packet.source || %{})
      event = %TelemetryPacket{packet: packet, metadata: metadata}
      {:ok, [event], state}
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
end
