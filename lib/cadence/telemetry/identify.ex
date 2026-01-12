defmodule Cadence.Telemetry.Identify do
  @moduledoc """
  Pure entry point for packet identification.
  """

  require Logger

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

  defp identify_packet(_packet, format, _event, _state) do
    {:error, {:unsupported_format, format}}
  end

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
    definition_set_id = Map.get(targets, target_id)

    with {:ok, def_set_id} <- validate_definition_set(definition_set_id, targets, target_id),
         {:ok, apid} <- validate_apid(apid, target_id),
         {:ok, packet_def} <- fetch_packet_def(catalog, def_set_id, apid, target_id) do
      {:ok, packet_def}
    else
      {:error, :unknown_packet} -> {:error, :unknown_packet}
    end
  end

  defp validate_definition_set(nil, targets, target_id) do
    available_targets = Map.keys(targets) |> Enum.take(5)

    Logger.debug(
      "Identify: target_id=#{inspect(target_id)} not in catalog. available targets (first 5): #{inspect(available_targets)}"
    )

    {:error, :unknown_packet}
  end

  defp validate_definition_set(def_set_id, _targets, _target_id), do: {:ok, def_set_id}

  defp validate_apid(apid, _target_id) when is_integer(apid), do: {:ok, apid}

  defp validate_apid(apid, target_id) do
    Logger.debug("Identify: invalid APID=#{inspect(apid)} for target=#{target_id}")
    {:error, :unknown_packet}
  end

  defp fetch_packet_def(catalog, def_set_id, apid, target_id) do
    case Map.get(catalog.by_apid, {def_set_id, apid}) do
      nil ->
        Logger.debug(
          "Identify: APID #{apid} not found for target=#{target_id}, definition_set=#{def_set_id}"
        )

        {:error, :unknown_packet}

      packet_def ->
        {:ok, packet_def}
    end
  end
end
