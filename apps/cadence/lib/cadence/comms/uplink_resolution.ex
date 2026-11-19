defmodule Cadence.Comms.UplinkResolution do
  @moduledoc """
  Which source endpoint carries a target's commands (DECISIONS #41): the one
  behind its **primary** effective route with an outbound leg (`outbound` or
  `bidirectional`, active and enabled). Routes materialize on the spacecraft's
  managed source endpoint, so one primary uplink route gives one endpoint.

  A target has a NO-GO when it has no primary uplink route, or when it has more
  than one, counted per profile rule (one rule across several stations is still
  one route choice), with the competing routes named so the UI can link to
  profile routing. An explicit endpoint chosen by the operator overrides this
  and is recorded as evidence.
  """

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore}
  alias Cadence.SourceEndpoints

  @uplink_directions [:outbound, :bidirectional]

  @type resolution ::
          {:ok, %{source_endpoint_id: binary(), via: :route | :override, routes: [map()]}}
          | {:error, :no_uplink_route, [map()]}
          | {:error, :multiple_primary_uplink_routes, [map()]}

  @doc """
  Annotates each draft target (`%{spacecraft_id, source_endpoint_id}`) with
  `:source_endpoint_id` and `:resolution`, or with `:failure` and `:failure_detail`.
  """
  @spec annotate(binary(), binary(), [map()]) :: [map()]
  def annotate(organization_id, mission_id, targets) do
    routes = routes_by_spacecraft(organization_id, mission_id)

    Enum.map(targets, fn target ->
      case resolve(target, Map.get(routes, target.spacecraft_id, [])) do
        {:ok, resolution} ->
          Map.merge(target, %{
            source_endpoint_id: resolution.source_endpoint_id,
            resolution: resolution
          })

        {:error, reason, detail} ->
          Map.merge(target, %{failure: reason, failure_detail: detail})
      end
    end)
  end

  @doc "Resolves one target from its routes."
  @spec resolve(map(), [RoutingRule.t()]) :: resolution()
  def resolve(%{source_endpoint_id: id}, routes) when is_binary(id),
    do:
      {:ok,
       %{
         source_endpoint_id: id,
         via: :override,
         routes: Enum.map(primary_uplinks(routes), &route/1)
       }}

  def resolve(%{spacecraft_id: spacecraft_id}, routes) do
    uplinks = primary_uplinks(routes)

    case uplinks |> Enum.group_by(&choice_key/1) |> Map.keys() do
      [] ->
        {:error, :no_uplink_route, Enum.map(routes, &route/1)}

      [_one] ->
        {:ok,
         %{
           source_endpoint_id: SourceEndpoints.managed_source_endpoint_id(spacecraft_id),
           via: :route,
           routes: Enum.map(uplinks, &route/1)
         }}

      _many ->
        {:error, :multiple_primary_uplink_routes, Enum.map(uplinks, &route/1)}
    end
  end

  defp primary_uplinks(routes) do
    Enum.filter(routes, fn %RoutingRule{} = route ->
      route.lifecycle_state == :active and route.enabled? and route.role == :primary and
        route.direction in @uplink_directions
    end)
  end

  defp choice_key(%RoutingRule{profile_rule_id: rule_id}) when is_binary(rule_id),
    do: {:profile_rule, rule_id}

  defp choice_key(%RoutingRule{routing_rule_id: id}), do: {:route, id}

  defp route(%RoutingRule{} = route) do
    %{
      id: route.routing_rule_id,
      name: route.display_name,
      direction: route.direction,
      role: route.role,
      origin: route.origin,
      transport_id: route.transport_id,
      ground_station_id: route.ground_station_id,
      profile_id: route.spacecraft_type_id,
      profile_rule_id: route.profile_rule_id
    }
  end

  defp routes_by_spacecraft(organization_id, mission_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules(mission_id)
    |> Enum.group_by(& &1.spacecraft_id)
  end
end
