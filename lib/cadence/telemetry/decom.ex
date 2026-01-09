defmodule Cadence.Telemetry.Decom do
  @moduledoc """
  Pure entry point for telemetry decommutation.
  """

  alias Cadence.Telemetry.{Decommutation, Packet}

  def run(%{packet_def: nil}, _state), do: {:skip, :missing_packet_def}
  def run(%{packet_format: nil}, _state), do: {:skip, :missing_packet_format}

  def run(%{packet: packet, packet_def: packet_def, packet_format: packet_format} = event, _state) do
    case Packet.get_payload(packet) do
      {:ok, payload} ->
        case Decommutation.decommutate(payload, packet_def, packet_format) do
          {:ok, raw_items} ->
            {:ok, %{event | raw_items: raw_items}}

          {:error, reason} ->
            {:error, {:decommutation_failed, packet_def.name, reason}}
        end

      {:error, reason} ->
        {:error, {:payload_extraction_failed, reason}}
    end
  end

  def run(_event, _state), do: {:error, :invalid_event}
end
