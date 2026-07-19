defmodule CadenceWeb.OpsDashboardShowLive.OperationalResourceScopePolicy do
  alias Cadence.Comms.{GroundStationStore, TransportStore}

  @moduledoc """
  Validation policy for dashboard runtime scopes backed by setup resources.
  """

  @spec valid_resource?(map(), map(), binary(), binary(), keyword()) :: boolean()
  def valid_resource?(current_scope, mission, scope_kind, resource_id, opts \\ [])

  def valid_resource?(current_scope, mission, scope_kind, resource_id, opts)
      when is_binary(scope_kind) and is_binary(resource_id) do
    with organization_id when is_binary(organization_id) <-
           map_value(current_scope, :organization_id),
         mission_id when is_binary(mission_id) <- map_value(mission, :mission_id) do
      case fetch_resource(scope_kind, organization_id, mission_id, resource_id, opts) do
        {:ok, _resource} -> true
        _other -> false
      end
    else
      _missing_context -> false
    end
  end

  def valid_resource?(_current_scope, _mission, _scope_kind, _resource_id, _opts), do: false

  defp fetch_resource("ground_station", organization_id, mission_id, resource_id, opts) do
    fetch_ground_station_fn(opts).(organization_id, mission_id, resource_id)
  end

  defp fetch_resource("source_endpoint", organization_id, mission_id, resource_id, opts) do
    fetch_source_endpoint_fn(opts).(organization_id, mission_id, resource_id)
  end

  defp fetch_resource("transport", organization_id, mission_id, resource_id, opts) do
    fetch_transport_fn(opts).(organization_id, mission_id, resource_id)
  end

  defp fetch_resource("link", organization_id, mission_id, resource_id, opts) do
    case fetch_link_assignment_fn(opts).(organization_id, mission_id, resource_id) do
      {:ok, _assignment} = result ->
        result

      _missing_assignment ->
        fetch_metadata_backed_link(organization_id, mission_id, resource_id, opts)
    end
  end

  defp fetch_resource(_scope_kind, _organization_id, _mission_id, _resource_id, _opts),
    do: {:error, :unsupported_scope_kind}

  defp fetch_ground_station_fn(opts),
    do:
      Keyword.get(
        opts,
        :fetch_ground_station,
        &GroundStationStore.fetch_ground_station/3
      )

  defp fetch_source_endpoint_fn(opts),
    do:
      Keyword.get(opts, :fetch_source_endpoint, &Cadence.SourceEndpoints.fetch_source_endpoint/3)

  defp fetch_transport_fn(opts),
    do: Keyword.get(opts, :fetch_transport, &TransportStore.fetch_transport/3)

  defp fetch_link_assignment_fn(opts),
    do: Keyword.get(opts, :fetch_link_assignment, &Cadence.Contacts.fetch_link_assignment/3)

  defp fetch_metadata_backed_link(organization_id, mission_id, link_id, opts) do
    resources =
      list_transports_fn(opts).(organization_id, mission_id) ++
        list_source_endpoints_fn(opts).(organization_id, mission_id) ++
        list_ground_stations_fn(opts).(organization_id, mission_id)

    case Enum.find(resources, &(resource_link_id(&1) == link_id)) do
      nil -> {:error, :link_scope_not_found}
      resource -> {:ok, resource}
    end
  end

  defp list_transports_fn(opts),
    do: Keyword.get(opts, :list_transports, &TransportStore.list_transports/2)

  defp list_source_endpoints_fn(opts),
    do:
      Keyword.get(opts, :list_source_endpoints, &Cadence.SourceEndpoints.list_source_endpoints/2)

  defp list_ground_stations_fn(opts),
    do:
      Keyword.get(
        opts,
        :list_ground_stations,
        &GroundStationStore.list_ground_stations/2
      )

  defp resource_link_id(resource) do
    map_value(resource, :link_id) ||
      map_value(resource, :link_assignment_id) ||
      metadata_value(resource, :link_id) ||
      metadata_value(resource, :link_assignment_id) ||
      metadata_value(resource, :link_assignment_ref) ||
      metadata_value(resource, :materialized_link_assignment_id)
  end

  defp metadata_value(resource, key) do
    resource
    |> map_value(:metadata)
    |> map_value(key)
  end

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_value(_map, _key), do: nil
end
