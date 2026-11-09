defmodule Cadence.Comms.RoutePlan do
  @moduledoc """
  Pure planning of one spacecraft's profile routes: from its effective routing rules
  (`Cadence.SpacecraftType.Effective`), the mission's stations and transports, the routes it
  should have, or the reasons it can't.

  Each route is one rule × station × leg. Its id is deterministic, so re-planning the same
  route yields the same row. A station's transport is the one the rule names, or else the
  station's single active transport that can carry the leg's direction.
  """

  alias Cadence.Comms.{GroundStation, RoutingRule, Transport}
  alias Cadence.Platform.ContentHash
  alias Cadence.SpacecraftType.RoutingRule, as: ProfileRule

  @type context :: %{
          stations: %{String.t() => GroundStation.t()},
          transports: %{String.t() => Transport.t()},
          transports_by_station: %{String.t() => [Transport.t()]}
        }

  @spec context([GroundStation.t()], [Transport.t()]) :: context()
  def context(stations, transports) do
    %{
      stations: Map.new(stations, &{&1.ground_station_id, &1}),
      transports: Map.new(transports, &{&1.transport_id, &1}),
      transports_by_station:
        transports
        |> Enum.reject(&is_nil(&1.ground_station_id))
        |> Enum.group_by(& &1.ground_station_id)
    }
  end

  @doc "Desired routes for a spacecraft, or `{:error, [%{path, message}]}`."
  @spec plan(map(), map(), String.t(), pos_integer(), context()) ::
          {:ok, [RoutingRule.t()]} | {:error, [map()]}
  def plan(spacecraft, effective, profile_id, profile_version, context) do
    results =
      for rule <- effective["routing_rules"],
          rule["enabled"],
          station <- rule["stations"],
          leg <- rule["legs"] do
        route(spacecraft, profile_id, profile_version, rule, station, leg, context)
      end

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {ok, []} -> {:ok, Enum.map(ok, &elem(&1, 1))}
      {_ok, errors} -> {:error, errors |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}
    end
  end

  @spec route_id(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def route_id(rule_id, spacecraft_id, station_id, leg) do
    "route_" <>
      String.slice(ContentHash.term_sha256({rule_id, spacecraft_id, station_id, leg}), 0, 32)
  end

  defp route(spacecraft, profile_id, profile_version, rule, station_ref, leg, context) do
    station_id = station_ref["ground_station_id"]
    direction = leg["direction"]

    with {:ok, station} <- station(context, station_id, rule),
         {:ok, transport} <-
           transport(context, station, station_ref["transport_id"], direction, rule) do
      {:ok,
       RoutingRule.new(%{
         routing_rule_id: route_id(rule["id"], spacecraft.spacecraft_id, station_id, direction),
         mission_id: spacecraft.mission_id,
         spacecraft_id: spacecraft.spacecraft_id,
         display_name:
           ProfileRule.render_name(rule["name_template"], %{
             "station" => station.code || station.display_name,
             "station_name" => station.display_name,
             "spacecraft" => spacecraft.display_name,
             "scid" => spacecraft.scid,
             "direction" => direction
           }),
         purpose_label: rule["label"],
         direction: if(direction == "downlink", do: :inbound, else: :outbound),
         transport_id: transport.transport_id,
         transport_version: transport.version,
         role: role(leg["role"]),
         origin: :profile,
         profile_rule_id: rule["id"],
         spacecraft_type_id: profile_id,
         spacecraft_type_version: profile_version,
         ground_station_id: station_id,
         leg_direction: direction
       })}
    end
  end

  defp station(context, station_id, rule) do
    case Map.get(context.stations, station_id) do
      nil -> {:error, error(rule, "Station #{station_id} doesn't exist or is archived")}
      station -> {:ok, station}
    end
  end

  defp transport(context, station, nil, direction, rule) do
    candidates =
      context.transports_by_station
      |> Map.get(station.ground_station_id, [])
      |> Enum.filter(&carries?(&1, direction))

    case candidates do
      [transport] ->
        {:ok, transport}

      [] ->
        {:error, error(rule, "#{station.display_name} has no active #{direction} transport")}

      _many ->
        {:error,
         error(rule, "#{station.display_name} has several #{direction} transports; pick one")}
    end
  end

  defp transport(context, station, transport_id, direction, rule) do
    case Map.get(context.transports, transport_id) do
      nil ->
        {:error,
         error(rule, "Transport #{transport_id} for #{station.display_name} doesn't exist")}

      transport ->
        if carries?(transport, direction),
          do: {:ok, transport},
          else: {:error, error(rule, "#{transport.display_name} can't carry #{direction}")}
    end
  end

  defp role("candidate"), do: :candidate
  defp role("contributing"), do: :contributing
  defp role(_primary), do: :primary

  defp carries?(%Transport{direction_capability: :bidirectional}, _direction), do: true
  defp carries?(%Transport{direction_capability: :inbound}, "downlink"), do: true
  defp carries?(%Transport{direction_capability: :outbound}, "uplink"), do: true
  defp carries?(_transport, _direction), do: false

  defp error(rule, message), do: %{path: "routing_rules.#{rule["id"]}", message: message}
end
