defmodule Cadence.Runtime.Telemetry.PipelineV2.Stages.IdentifyStage do
  @moduledoc """
  Pipeline stage that identifies packet type via PacketIdentifier.

  This is the first processing stage in the pipeline. It:
  - Determines packet format (CCSDS, simulator, etc.)
  - Looks up packet definition from ETS cache
  - Enriches the event with packet_def and packet_format

  ## Input

  PipelineEvent with:
  - `packet` - Raw Packet struct

  ## Output

  PipelineEvent enriched with:
  - `packet_def` - Packet definition from database (items, conversions, etc.)
  - `packet_format` - Format atom (:ccsds, :simulator)
  """

  use Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour

  alias Cadence.Runtime.Telemetry.PacketIdentifier
  alias Cadence.Telemetry.Packet

  @impl true
  def stage_name, do: :identify

  @impl true
  def process(event, state) do
    packet = event.packet
    packet_format = Packet.get_format(packet)

    case identify_packet(packet, packet_format, state.mission_id) do
      {:ok, packet_def} ->
        {:ok,
         %{
           event
           | packet_def: packet_def,
             packet_format: packet_format
         }}

      {:error, :unknown_packet} ->
        {:skip, :unknown_packet}

      {:error, reason} ->
        {:error, {:identify_failed, reason}}
    end
  end

  # Identify packet based on format
  defp identify_packet(%Packet{} = packet, :ccsds, mission_id) do
    case Packet.get_apid(packet) do
      nil ->
        Logger.debug(
          "CCSDS packet missing APID, raw header: #{inspect(:binary.part(packet.raw, 0, min(6, byte_size(packet.raw))), limit: :infinity)}"
        )

        {:error, :missing_apid}

      apid ->
        # Get target_id from packet for target-scoped definition lookup
        target_id = packet.target_id || "UNKNOWN"
        PacketIdentifier.identify_by_apid(mission_id, target_id, apid)
    end
  end

  defp identify_packet(%Packet{} = packet, :simulator, mission_id) do
    with {:ok, _type_byte} <- Packet.get_type_byte(packet),
         {:ok, target_id} <- extract_target_id(packet.raw),
         {:ok, packet_def} <- PacketIdentifier.identify(mission_id, packet.raw) do
      {:ok, Map.put(packet_def, :target_id, target_id)}
    end
  end

  defp identify_packet(_packet, format, _mission_id) do
    {:error, {:unsupported_format, format}}
  end

  defp extract_target_id(<<_type::8, target_id_len::8, rest::binary>>)
       when byte_size(rest) >= target_id_len do
    <<target_id::binary-size(target_id_len), _payload::binary>> = rest
    {:ok, target_id}
  end

  defp extract_target_id(_raw), do: {:error, :malformed_packet}
end
