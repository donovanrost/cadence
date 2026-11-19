defmodule Cadence.Contacts.SingleBookings.Routes do
  @moduledoc """
  A16b (user ruling, fe-ops, ux): the routes Book a pass can search for one spacecraft, for the
  route picker, with the search limits. They're the spacecraft's READY downlink routes, the same set
  the search fans out over.

  A route names its station only when it PINS one (its routing rule's station, else its
  transport's, the same rule uplink legs use); otherwise the provider picks among its stations and
  each offer names its own. `uplink`: for a pinned route, whether this spacecraft has a primary
  uplink path at that station via the route's provider (offers' `uplink_capable`); for an unpinned
  one, `false` when it has none via that provider at all, `nil` when it depends on the station.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.{RoutingRuleStore, StationRefs, TransportStore}
  alias Cadence.Contacts.{ProviderScheduling, UplinkLegs}
  alias Cadence.Contacts.SingleBookings.Search
  alias Cadence.SpacecraftStore

  @spec list(Scope.t(), binary(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def list(%Scope{} = scope, mission, spacecraft_id) when is_binary(spacecraft_id) do
    org = scope.organization_id

    with :ok <-
           Policy.authorize(scope, :operate_mission, %{organization_id: org, mission_id: mission}),
         {:ok, sc} <- spacecraft(org, mission, spacecraft_id),
         {:ok, %{routes: routes, findings: findings}} <-
           ProviderScheduling.list_ready_downlink_routes(org, mission, sc.spacecraft_id) do
      stations = StationRefs.index(org, mission)
      pins = pins(org, mission, sc.spacecraft_id)
      uplink = UplinkLegs.uplink_stations(org, mission, sc.spacecraft_id)

      {:ok,
       %{
         spacecraft: %{id: sc.spacecraft_id, name: sc.display_name},
         routes:
           Enum.map(routes, &route(&1, Map.get(pins, &1.routing_rule_id), stations, uplink)),
         not_ready: Enum.map(findings, &%{code: to_string(&1.code), message: &1.message}),
         limits: Search.limits()
       }}
    end
  end

  def list(_scope, _mission, _spacecraft_id),
    do: {:error, {:invalid, %{"spacecraft_id" => "Choose a spacecraft"}}}

  defp spacecraft(org, mission, id) do
    case SpacecraftStore.fetch_spacecraft(org, mission, id) do
      {:ok, sc} -> {:ok, sc}
      _missing -> {:error, :not_found}
    end
  end

  # routing_rule_id => the station ref the rule (else its transport) pins, or nil.
  defp pins(org, mission, spacecraft_id) do
    org
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission, spacecraft_id)
    |> Map.new(fn rule ->
      transport_station =
        case TransportStore.fetch_transport_version(
               org,
               mission,
               rule.transport_id,
               rule.transport_version
             ) do
          {:ok, transport} -> transport.ground_station_id
          _missing -> nil
        end

      {rule.routing_rule_id, rule.ground_station_id || transport_station}
    end)
  end

  defp route(route, pinned, stations, uplink) do
    by_provider = Map.get(uplink, route.provider_id, [])

    %{
      key: route.route_key,
      name: route.route_display_name,
      provider: %{id: route.provider_id, name: route.provider_display_name},
      transport: %{
        id: route.transport_id,
        version: route.transport_version,
        name: route.transport_display_name
      },
      service_name: route.service_display_name,
      station: pinned && StationRefs.resolve(pinned, stations),
      uplink: uplink?(pinned, by_provider)
    }
  end

  defp uplink?(_pinned, []), do: false
  defp uplink?(nil, _stations), do: nil
  defp uplink?(pinned, stations), do: pinned in stations
end
