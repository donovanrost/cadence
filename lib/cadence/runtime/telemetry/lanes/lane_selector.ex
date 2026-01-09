defmodule Cadence.Runtime.Telemetry.Lanes.LaneSelector do
  @moduledoc """
  Selects a lane for incoming telemetry based on packet metadata and selectors.
  """

  alias Cadence.Telemetry.Packet

  @type lane_config :: %{
          name: atom(),
          selectors: map()
        }

  @spec select_lane(Packet.t(), map(), [lane_config()]) :: atom()
  def select_lane(packet, metadata, lanes) do
    lane_override =
      metadata[:lane] ||
        metadata[:telemetry_lane] ||
        metadata[:lane_override]

    case resolve_lane_override(lane_override, lanes) do
      {:ok, override} -> override
      :error -> select_by_rules(packet, metadata, lanes)
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

  defp select_by_rules(packet, metadata, lanes) do
    lanes
    |> Enum.sort_by(&Map.get(&1, :priority, 0))
    |> Enum.find_value(:payload, fn lane ->
      if lane_match?(lane, packet, metadata) do
        lane.name
      else
        false
      end
    end)
  end

  defp lane_match?(lane, packet, metadata) do
    selectors = Map.get(lane, :selectors, %{})

    apid = Packet.get_apid(packet) || metadata[:apid]
    target_id = metadata[:target_id] || packet.target_id
    packet_name = packet.packet_name || metadata[:packet_name]

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
    interfaces = Map.get(selectors, :interface_ids)
    sources = Map.get(selectors, :sources)

    interface_match =
      case {interfaces, metadata[:interface_id]} do
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

    interface_match and source_match
  end
end
