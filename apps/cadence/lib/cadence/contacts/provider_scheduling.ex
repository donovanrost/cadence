defmodule Cadence.Contacts.ProviderScheduling do
  @moduledoc """
  Resolves mission comms configuration into provider-ready downlink routes.

  This keeps provider mapping, readiness findings, and opportunity validation
  outside the web layer. Route keys are re-resolved in organization and mission
  scope before every search or reservation.
  """

  alias Cadence.Contacts
  alias Cadence.Contacts.{LinkAssignment, ProviderBooking, ProviderClients.Registry}
  alias Cadence.GroundNetworks.{Opportunity, ProviderContext}
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @default_result_limit 100
  @maximum_horizon_seconds 7 * 24 * 60 * 60
  @past_grace_seconds 60

  @type ready_route :: %{
          route_key: binary(),
          spacecraft_id: binary(),
          spacecraft_display_name: binary(),
          provider_spacecraft_ref: binary(),
          source_endpoint_id: binary(),
          link_assignment_id: binary(),
          path_template_id: binary(),
          path_template_version: pos_integer(),
          provider_profile_id: binary(),
          provider_profile_version: pos_integer(),
          service_profile_ref: binary(),
          delivery_profile_ref: binary(),
          provider_display_name: binary(),
          route_display_name: binary(),
          client: module()
        }

  @spec list_ready_downlink_routes(binary(), binary(), binary()) ::
          {:ok, %{routes: [ready_route()], findings: [map()]}} | {:error, term()}
  def list_ready_downlink_routes(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      endpoints =
        SourceEndpoints.list_source_endpoints(
          organization_id,
          mission_id,
          spacecraft_id: spacecraft_id
        )

      assignments = Contacts.list_link_assignments(organization_id, mission_id)

      {routes, findings} =
        endpoints
        |> Enum.reduce({[], []}, fn endpoint, acc ->
          resolve_endpoint(spacecraft, endpoint, assignments, acc)
        end)
        |> add_missing_endpoint_finding(endpoints, spacecraft_id)

      {:ok,
       %{
         routes: Enum.sort_by(routes, &{&1.provider_display_name, &1.route_display_name}),
         findings: Enum.uniq_by(findings, &{&1.code, &1[:resource_id]})
       }}
    end
  end

  @spec resolve_ready_downlink_route(binary(), binary(), binary(), binary()) ::
          {:ok, ready_route()} | {:error, term()}
  def resolve_ready_downlink_route(organization_id, mission_id, spacecraft_id, route_key) do
    with {:ok, %{routes: routes}} <-
           list_ready_downlink_routes(organization_id, mission_id, spacecraft_id) do
      case Enum.find(routes, &(&1.route_key == route_key)) do
        nil -> {:error, :provider_scheduling_route_not_ready}
        route -> {:ok, route}
      end
    end
  end

  @spec search_opportunities(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{opportunities: [map()], route: ready_route()}} | {:error, term()}
  def search_opportunities(organization_id, mission_id, route_key, window, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(route_key) and
             is_map(window) and is_list(opts) do
    spacecraft_id = Map.get(window, "spacecraft_id", Map.get(window, :spacecraft_id))

    with true <- is_binary(spacecraft_id) and spacecraft_id != "",
         {:ok, route} <-
           resolve_ready_downlink_route(
             organization_id,
             mission_id,
             spacecraft_id,
             route_key
           ),
         {:ok, starts_at} <- parse_time(window, :starts_at),
         {:ok, ends_at} <- parse_time(window, :ends_at),
         :ok <- validate_window(starts_at, ends_at, opts),
         result_limit <- Keyword.get(opts, :result_limit, @default_result_limit),
         {:ok, response} <-
           ProviderBooking.search(
             organization_id,
             mission_id,
             route.provider_profile_id,
             %{
               "spacecraft_refs" => [route.provider_spacecraft_ref],
               "ground_station_refs" => [],
               "service_profile_ref" => route.service_profile_ref,
               "starts_at" => DateTime.to_iso8601(starts_at),
               "ends_at" => DateTime.to_iso8601(ends_at),
               "page_size" => result_limit,
               "cursor" => nil
             },
             Keyword.put(opts, :provider_profile_version, route.provider_profile_version)
           ),
         {:ok, opportunities} <-
           validate_opportunities(response, route, starts_at, ends_at, result_limit) do
      {:ok,
       %{
         route: route,
         opportunities:
           Enum.map(opportunities, fn opportunity ->
             opportunity
             |> Map.put("route_key", route.route_key)
             |> Map.put("delivery_profile_ref", route.delivery_profile_ref)
           end)
       }}
    else
      false -> {:error, :spacecraft_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_endpoint(spacecraft, endpoint, assignments, {routes, findings}) do
    if blank?(endpoint.source_ref) do
      {routes,
       [
         finding(
           :missing_provider_spacecraft_reference,
           "Source endpoint needs a provider spacecraft reference.",
           endpoint.source_endpoint_id
         )
         | findings
       ]}
    else
      resolve_endpoint_assignments(spacecraft, endpoint, assignments, {routes, findings})
    end
  end

  defp resolve_endpoint_assignments(spacecraft, endpoint, assignments, {routes, findings}) do
    matching_assignments =
      Enum.filter(assignments, fn assignment ->
        assignment.lifecycle_state == :active and assignment.direction == :downlink and
          assignment.spacecraft_id == spacecraft.spacecraft_id and
          assignment.source_endpoint_ref == endpoint.source_endpoint_id
      end)

    if matching_assignments == [] do
      {routes,
       [
         finding(
           :missing_downlink_route,
           "Source endpoint needs an active downlink link assignment.",
           endpoint.source_endpoint_id
         )
         | findings
       ]}
    else
      Enum.reduce(matching_assignments, {routes, findings}, fn assignment, acc ->
        resolve_assignment(spacecraft, endpoint, assignment, acc)
      end)
    end
  end

  defp resolve_assignment(spacecraft, endpoint, assignment, {routes, findings}) do
    case Contacts.fetch_path_template_version(
           spacecraft.organization_id,
           spacecraft.mission_id,
           assignment.path_template_id,
           assignment.path_template_version
         ) do
      {:ok, template} ->
        resolve_template(spacecraft, endpoint, assignment, template, {routes, findings})

      {:error, _reason} ->
        {routes,
         [
           finding(
             :missing_downlink_route,
             "Assigned downlink path template version is not available.",
             assignment.link_assignment_id
           )
           | findings
         ]}
    end
  end

  defp resolve_template(spacecraft, endpoint, assignment, template, {routes, findings}) do
    profile_refs = provider_profile_refs(assignment, template)

    if profile_refs == [] do
      {routes,
       [
         finding(
           :missing_provider_profile,
           "Downlink path needs an active provider profile.",
           template.path_template_id
         )
         | findings
       ]}
    else
      Enum.reduce(profile_refs, {routes, findings}, fn profile_ref, acc ->
        resolve_provider(spacecraft, endpoint, assignment, template, profile_ref, acc)
      end)
    end
  end

  defp resolve_provider(
         spacecraft,
         endpoint,
         assignment,
         template,
         profile_ref,
         {routes, findings}
       ) do
    case Contacts.fetch_provider_profile_version(
           spacecraft.organization_id,
           spacecraft.mission_id,
           profile_ref["provider_profile_id"],
           profile_ref["version"]
         ) do
      {:ok, provider_profile} ->
        case provider_readiness(provider_profile) do
          {:ok, client} ->
            route =
              ready_route(
                spacecraft,
                endpoint,
                assignment,
                template,
                provider_profile,
                client
              )

            {[route | routes], findings}

          {:error, code, message} ->
            {routes, [finding(code, message, provider_profile.provider_profile_id) | findings]}
        end

      {:error, _reason} ->
        {routes,
         [
           finding(
             :missing_provider_profile,
             "Referenced provider profile version is not available.",
             profile_ref["provider_profile_id"]
           )
           | findings
         ]}
    end
  end

  defp provider_readiness(provider_profile) do
    scheduling = Map.get(provider_profile.configuration, "scheduling", %{})

    with :ok <- validate_active_provider(provider_profile),
         :ok <- validate_scheduling_api(scheduling),
         :ok <- validate_environment_scope(scheduling),
         :ok <- validate_profile_reference(scheduling, "service_profile_ref"),
         :ok <- validate_profile_reference(scheduling, "delivery_profile_ref") do
      fetch_scheduling_client(provider_profile)
    end
  end

  defp validate_active_provider(provider_profile) do
    if provider_profile.lifecycle_state == :active do
      :ok
    else
      {:error, :inactive_provider_profile, "Provider profile is not active."}
    end
  end

  defp validate_scheduling_api(scheduling) do
    if blank?(scheduling["client"]) or blank?(scheduling["base_url"]) do
      {:error, :missing_scheduling_client, "Provider scheduling API is not configured."}
    else
      :ok
    end
  end

  defp validate_environment_scope(scheduling) do
    if blank?(scheduling["environment_ref"] || scheduling["run_id"]) do
      {:error, :missing_provider_environment, "Provider environment reference is required."}
    else
      :ok
    end
  end

  defp validate_profile_reference(scheduling, key) do
    if blank?(scheduling[key]) do
      {:error, :missing_provider_profile_reference, "Provider #{key} is required."}
    else
      :ok
    end
  end

  defp fetch_scheduling_client(provider_profile) do
    with {:ok, context} <- ProviderContext.from_provider_profile(provider_profile) do
      case Registry.fetch(context) do
        {:ok, client} ->
          {:ok, client}

        {:error, _reason} ->
          {:error, :unknown_scheduling_client, "Provider scheduling client is not supported."}
      end
    end
  end

  defp ready_route(spacecraft, endpoint, assignment, template, provider_profile, client) do
    route_key =
      [
        spacecraft.spacecraft_id,
        endpoint.source_endpoint_id,
        assignment.link_assignment_id,
        template.path_template_id,
        template.version,
        provider_profile.provider_profile_id,
        provider_profile.version
      ]
      |> Enum.join(":")

    %{
      route_key: route_key,
      spacecraft_id: spacecraft.spacecraft_id,
      spacecraft_display_name: spacecraft.display_name,
      provider_spacecraft_ref: endpoint.source_ref,
      source_endpoint_id: endpoint.source_endpoint_id,
      link_assignment_id: assignment.link_assignment_id,
      path_template_id: template.path_template_id,
      path_template_version: template.version,
      provider_profile_id: provider_profile.provider_profile_id,
      provider_profile_version: provider_profile.version,
      service_profile_ref:
        get_in(provider_profile.configuration, ["scheduling", "service_profile_ref"]),
      delivery_profile_ref:
        get_in(provider_profile.configuration, ["scheduling", "delivery_profile_ref"]),
      provider_display_name:
        display_name(provider_profile.metadata, provider_profile.provider_profile_id),
      route_display_name: display_name(template.metadata, template.path_id),
      client: client
    }
  end

  defp provider_profile_refs(%LinkAssignment{provider_profile_refs: refs}, _template)
       when refs != [],
       do: refs

  defp provider_profile_refs(_assignment, template), do: template.provider_profile_refs

  defp add_missing_endpoint_finding({routes, findings}, [], spacecraft_id) do
    {routes,
     [
       finding(
         :missing_source_endpoint,
         "Spacecraft needs a source endpoint before contacts can be scheduled.",
         spacecraft_id
       )
       | findings
     ]}
  end

  defp add_missing_endpoint_finding(result, _endpoints, _spacecraft_id), do: result

  defp validate_window(starts_at, ends_at, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    cond do
      not DateTime.before?(starts_at, ends_at) ->
        {:error, :invalid_opportunity_window}

      DateTime.before?(starts_at, DateTime.add(now, -@past_grace_seconds, :second)) ->
        {:error, :opportunity_window_in_past}

      DateTime.diff(ends_at, starts_at, :second) > @maximum_horizon_seconds ->
        {:error, :opportunity_window_too_large}

      true ->
        :ok
    end
  end

  defp validate_opportunities(response, route, starts_at, ends_at, result_limit) do
    opportunities = Map.get(response, :data, Map.get(response, "data"))

    if is_list(opportunities) do
      validate_opportunity_list(opportunities, route, starts_at, ends_at, result_limit)
    else
      {:error, {:malformed_provider_response, :opportunities}}
    end
  end

  defp validate_opportunity_list(opportunities, route, starts_at, ends_at, result_limit) do
    if length(opportunities) > result_limit do
      {:error, {:provider_result_limit_exceeded, result_limit}}
    else
      normalize_opportunities(opportunities, route, starts_at, ends_at)
    end
  end

  defp normalize_opportunities(opportunities, route, starts_at, ends_at) do
    reducer = &collect_opportunity(&1, &2, route, starts_at, ends_at)

    case Enum.reduce_while(opportunities, {:ok, []}, reducer) do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp collect_opportunity(opportunity, {:ok, acc}, route, starts_at, ends_at) do
    case validate_opportunity(opportunity, route, starts_at, ends_at) do
      {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp validate_opportunity(%Opportunity{} = opportunity, route, window_starts_at, window_ends_at) do
    with true <- opportunity.spacecraft_ref == route.provider_spacecraft_ref,
         true <- opportunity.service_profile_ref == route.service_profile_ref,
         starts_at = opportunity.starts_at,
         ends_at = opportunity.ends_at,
         true <- DateTime.compare(starts_at, window_starts_at) in [:eq, :gt],
         true <- DateTime.compare(ends_at, window_ends_at) in [:eq, :lt] do
      {:ok,
       opportunity
       |> Opportunity.to_map()}
    else
      false -> {:error, {:invalid_provider_opportunity, opportunity.id}}
    end
  end

  defp validate_opportunity(opportunity, route, window_starts_at, window_ends_at)
       when is_map(opportunity) do
    case Opportunity.from_external(opportunity) do
      {:ok, normalized} ->
        validate_opportunity(normalized, route, window_starts_at, window_ends_at)

      {:error, _reason} ->
        {:error, {:invalid_provider_opportunity, opportunity["id"] || :shape}}
    end
  end

  defp validate_opportunity(_opportunity, _route, _starts_at, _ends_at),
    do: {:error, {:invalid_provider_opportunity, :shape}}

  defp parse_time(map, key) do
    value = Map.get(map, key, Map.get(map, Atom.to_string(key)))

    case value do
      %DateTime{} = datetime ->
        {:ok, datetime}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          _error -> {:error, {:invalid_datetime, key}}
        end

      _other ->
        {:error, {:invalid_datetime, key}}
    end
  end

  defp finding(code, message, resource_id) do
    %{code: code, message: message, resource_id: resource_id, remediation: :comms}
  end

  defp display_name(metadata, fallback),
    do: Map.get(metadata, "display_name", Map.get(metadata, :display_name, fallback))

  defp blank?(value), do: not (is_binary(value) and String.trim(value) != "")
end
