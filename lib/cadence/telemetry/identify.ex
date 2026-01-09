defmodule Cadence.Telemetry.Identify do
  @moduledoc """
  Pure entry point for packet identification.
  """

  alias Cadence.Telemetry.Packet

  def run(event, state) do
    packet = event.packet
    packet_format = Packet.get_format(packet)

    case identify_packet(packet, packet_format, event, state) do
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

  defp identify_packet(%Packet{} = packet, :ccsds, event, state) do
    fetch_packet_def_from_catalog(packet, :ccsds, event, state)
  end

  defp identify_packet(%Packet{} = packet, :simulator, event, state) do
    fetch_packet_def_from_catalog(packet, :simulator, event, state)
  end

  defp identify_packet(_packet, format, _event, _state) do
    {:error, {:unsupported_format, format}}
  end

  defp extract_target_id(<<_type::8, target_id_len::8, rest::binary>>)
       when byte_size(rest) >= target_id_len do
    <<target_id::binary-size(target_id_len), _payload::binary>> = rest
    {:ok, target_id}
  end

  defp extract_target_id(_raw), do: {:error, :malformed_packet}

  defp fetch_packet_def_from_catalog(packet, format, event, state) do
    case state[:config_bundle] do
      %{packet_catalog: %{targets: targets} = catalog} ->
        lookup_packet_def(packet, format, event, targets, catalog)

      _ ->
        {:error, :missing_packet_catalog}
    end
  end

  defp lookup_packet_def(packet, :ccsds, event, targets, catalog) do
    apid = event.apid || Packet.get_apid(packet)
    target_id = event.target_id || packet.target_id || "UNKNOWN"

    case {Map.get(targets, target_id), apid} do
      {definition_set_id, apid} when is_integer(apid) and not is_nil(definition_set_id) ->
        case Map.get(catalog.by_apid, {definition_set_id, apid}) do
          nil -> {:error, :unknown_packet}
          packet_def -> {:ok, packet_def}
        end

      _ ->
        {:error, :unknown_packet}
    end
  end

  defp lookup_packet_def(packet, :simulator, _event, targets, catalog) do
    with {:ok, type_byte} <- Packet.get_type_byte(packet),
         {:ok, target_id} <- extract_target_id(packet.raw),
         definition_set_id when not is_nil(definition_set_id) <- Map.get(targets, target_id),
         packet_def when not is_nil(packet_def) <-
           Map.get(catalog.by_type, {definition_set_id, type_byte}) do
      {:ok, Map.put(packet_def, :target_id, target_id)}
    else
      _ -> {:error, :unknown_packet}
    end
  end
end
