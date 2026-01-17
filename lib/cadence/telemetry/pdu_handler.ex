defmodule Cadence.Telemetry.PDUHandler do
  @moduledoc """
  Telemetry handler that converts space packet PDUs into telemetry events.
  """

  @behaviour Cadence.CCSDS.PDUHandler

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Downlink.PacketAdapter
  alias Cadence.Events.TelemetryPacket

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
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
end
