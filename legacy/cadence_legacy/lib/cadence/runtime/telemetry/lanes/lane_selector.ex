defmodule Cadence.Runtime.Telemetry.Lanes.LaneSelector do
  @moduledoc """
  Selects a lane for incoming telemetry based on packet metadata and selectors.
  """

  alias Cadence.Telemetry.SpacePacket

  @type lane_config :: %{
          name: atom(),
          selectors: map()
        }

  @spec select_lane_envelope(
          Cadence.Telemetry.PacketEnvelope.t(),
          Cadence.Telemetry.ParsedUnit.t() | nil,
          map(),
          [lane_config()]
        ) ::
          atom()
  def select_lane_envelope(envelope, parsed_unit, metadata, lanes) do
    lane_override =
      metadata[:lane] ||
        metadata[:telemetry_lane] ||
        metadata[:lane_override]

    case resolve_lane_override(lane_override, lanes) do
      {:ok, override} -> override
      :error -> select_by_rules_envelope(envelope, parsed_unit, metadata, lanes)
    end
  end

  defp resolve_lane_override(nil, _lanes), do: :error
  defp resolve_lane_override(lane, _lanes) when is_atom(lane), do: {:ok, lane}

  defp resolve_lane_override(lane, lanes) when is_binary(lane) do
    case Enum.find(lanes, fn config -> lane_name_match?(config.name, lane) end) do
      nil -> :error
      config -> {:ok, config.name}
    end
  end

  defp resolve_lane_override(_, _lanes), do: :error

  defp lane_name_match?(name, lane_string) when is_atom(name) do
    Atom.to_string(name) == lane_string
  end

  defp lane_name_match?(name, lane_string) when is_binary(name) do
    name == lane_string
  end

  defp lane_name_match?(_, _), do: false

  defp select_by_rules_envelope(envelope, parsed_unit, metadata, lanes) do
    lanes
    |> Enum.sort_by(&Map.get(&1, :priority, 0))
    |> Enum.find_value(:payload, fn lane ->
      if lane_match_envelope?(lane, envelope, parsed_unit, metadata) do
        lane.name
      else
        false
      end
    end)
  end

  defp lane_match_envelope?(lane, envelope, parsed_unit, metadata) do
    selectors = Map.get(lane, :selectors, %{})
    apid = apid_from_parsed(parsed_unit) || evidence_apid(envelope) || metadata[:apid]
    target_id = metadata[:target_id]
    packet_name = metadata[:packet_name]

    apid_match?(selectors, apid) and
      target_match?(selectors, target_id) and
      packet_match?(selectors, packet_name) and
      source_match?(selectors, metadata)
  end

  defp apid_match?(selectors, apid) do
    apids = Map.get(selectors, :apids)
    apid_ranges = Map.get(selectors, :apid_ranges)

    list_match?(apids, apid) and range_match?(apid_ranges, apid)
  end

  defp list_match?(nil, _value), do: true
  defp list_match?(list, value) when is_list(list), do: value in list
  defp list_match?(_, _value), do: false

  defp range_match?(nil, _apid), do: true

  defp range_match?(ranges, apid) when is_list(ranges) and is_integer(apid) do
    Enum.any?(ranges, fn {min, max} -> apid >= min and apid <= max end)
  end

  defp range_match?(_, _apid), do: false

  defp target_match?(selectors, target_id) do
    targets = Map.get(selectors, :targets)

    case {targets, target_id} do
      {nil, _} -> true
      {list, id} when is_list(list) -> id in list
      _ -> false
    end
  end

  defp packet_match?(selectors, packet_name) do
    packets = Map.get(selectors, :packet_names)

    case {packets, packet_name} do
      {nil, _} -> true
      {list, name} when is_list(list) -> name in list
      _ -> false
    end
  end

  defp source_match?(selectors, metadata) do
    transports = Map.get(selectors, :transport_ids)
    sources = Map.get(selectors, :sources)

    transport_match =
      case {transports, metadata[:transport_id]} do
        {nil, _} -> true
        {list, id} when is_list(list) -> id in list
        _ -> false
      end

    source_match =
      case {sources, metadata[:source]} do
        {nil, _} -> true
        {list, source} when is_list(list) -> source in list
        _ -> false
      end

    transport_match and source_match
  end

  defp apid_from_parsed({:space_packet, %SpacePacket{} = packet}) do
    SpacePacket.get_apid(packet)
  end

  defp apid_from_parsed(_), do: nil

  defp evidence_apid(%Cadence.Telemetry.PacketEnvelope{evidence: evidence}) do
    evidence
    |> Enum.find(&(&1.kind == :apid))
    |> case do
      nil -> nil
      entry -> entry.value
    end
  end
end
