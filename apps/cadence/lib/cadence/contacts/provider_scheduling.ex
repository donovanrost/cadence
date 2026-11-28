defmodule Cadence.Contacts.ProviderScheduling do
  @moduledoc """
  Resolves durable mission routing into provider opportunity-search routes.

  External scheduling is available only when an enabled Routing Rule selects
  an exact provider-managed Transport version. The Transport binds the exact
  Mission Provider, Service Profile, Delivery Profile, and runtime bridge that
  a later reservation must snapshot before mutating provider state.
  """

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport}

  alias Cadence.Contacts.{
    LinkAssignment,
    ProviderClients.Registry,
    ProviderScheduling.RoutePins
  }

  alias Cadence.Control.Providers, as: ProviderControl

  alias Cadence.GroundNetworks.{
    Opportunity,
    ProviderContext,
    Validation
  }

  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.SpacecraftStore

  @default_result_limit 100
  @maximum_horizon_seconds 7 * 24 * 60 * 60
  @past_grace_seconds 60

  @type profile_ref :: map()
  @type ready_route :: %{
          route_key: binary(),
          spacecraft_id: binary(),
          spacecraft_display_name: binary(),
          provider_spacecraft_ref: binary(),
          source_endpoint_id: binary(),
          routing_rule_id: binary(),
          link_assignment_id: binary(),
          path_template_id: binary(),
          path_template_version: pos_integer(),
          transport_id: binary(),
          transport_version: pos_integer(),
          transport_display_name: binary(),
          provider_id: binary(),
          provider_version: pos_integer(),
          provider_account_id: binary() | nil,
          provider_account_version: pos_integer() | nil,
          provider_account_grant_id: binary() | nil,
          provider_account_grant_version: pos_integer() | nil,
          provider_profile_id: binary(),
          provider_profile_version: pos_integer(),
          service_profile_ref: profile_ref(),
          delivery_profile_ref: profile_ref(),
          delivery_policy_document: map(),
          provider_display_name: binary(),
          service_display_name: binary(),
          delivery_display_name: binary(),
          delivery_operator_summary: binary(),
          route_display_name: binary(),
          client: module()
        }

  @spec list_ready_downlink_routes(binary(), binary(), binary()) ::
          {:ok, %{routes: [ready_route()], findings: [map()]}} | {:error, term()}
  def list_ready_downlink_routes(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    with {:ok, routes, _providers} <-
           list_ready_downlink_routes_for_fleet(organization_id, mission_id, [spacecraft_id]) do
      Map.get(routes, spacecraft_id, {:error, :spacecraft_not_found})
    end
  end

  @doc false
  def list_ready_downlink_routes_for_fleet(organization_id, mission_id, spacecraft_ids) do
    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(
             organization_id,
             mission_id,
             spacecraft_ids
           ) do
      endpoints =
        SourceEndpoints.list_source_endpoints_for_spacecrafts(
          organization_id,
          mission_id,
          spacecraft_ids
        )

      rules =
        spacecraft_ids
        |> Enum.chunk_every(500)
        |> Enum.flat_map(fn ids ->
          RoutingRuleStore.list_routing_rules_for_spacecrafts(organization_id, mission_id, ids)
        end)
        |> Map.new(fn {id, rules} -> {id, Enum.filter(rules, &downlink_rule?/1)} end)

      pins = RoutePins.load(organization_id, mission_id, rules |> Map.values() |> List.flatten())

      routes =
        Map.new(spacecraft, fn {id, item} ->
          {routes, findings} =
            resolve_rules(item, Map.get(endpoints, id, []), Map.fetch!(rules, id), pins)

          {id,
           {:ok,
            %{
              routes: Enum.sort_by(routes, &{&1.provider_display_name, &1.route_display_name}),
              findings: Enum.uniq_by(findings, &{&1.code, &1[:resource_id]})
            }}}
        end)

      {:ok, routes, pins.providers}
    end
  end

  @spec resolve_ready_downlink_route(binary(), binary(), binary(), binary()) ::
          {:ok, ready_route()} | {:error, term()}
  def resolve_ready_downlink_route(organization_id, mission_id, spacecraft_id, route_key) do
    with {:ok, %{routes: routes, findings: findings}} <-
           list_ready_downlink_routes(organization_id, mission_id, spacecraft_id) do
      case Enum.find(routes, &(&1.route_key == route_key)) do
        nil -> unavailable_route(findings, spacecraft_id, route_key)
        route -> {:ok, route}
      end
    end
  end

  defp unavailable_route(findings, spacecraft_id, route_key) do
    if Enum.any?(findings, fn finding ->
         finding.code == :transport_archived and
           String.starts_with?(route_key, "#{spacecraft_id}:#{finding.resource_id}:")
       end) do
      {:error, :transport_archived}
    else
      {:error, :provider_scheduling_route_not_ready}
    end
  end

  @doc "The immutable route pins reviewed before search and sealed into reservation capabilities."
  def route_evidence(route) do
    %{
      "provider_id" => route.provider_id,
      "provider_version" => route.provider_version,
      "transport_id" => route.transport_id,
      "transport_version" => route.transport_version,
      "provider_profile_id" => route.provider_profile_id,
      "provider_profile_version" => route.provider_profile_version,
      "routing_rule_id" => route.routing_rule_id,
      "path_template_id" => route.path_template_id,
      "path_template_version" => route.path_template_version,
      "source_endpoint_id" => route.source_endpoint_id,
      "provider_spacecraft_ref" => route.provider_spacecraft_ref,
      "service_profile_ref" => route.service_profile_ref,
      "delivery_profile_ref" => route.delivery_profile_ref
    }
  end

  @doc "Bounded semantic route labels and exact configuration evidence."
  def route_summary(r) do
    %{
      key: r.route_key,
      spacecraft_id: r.spacecraft_id,
      provider: route_label(r.provider_display_name),
      transport: route_label(r.transport_display_name),
      service: route_label(r.service_display_name),
      delivery: route_label(r.delivery_display_name),
      delivery_summary: route_label(r.delivery_operator_summary),
      evidence: route_evidence(r)
    }
  end

  defp route_label(value) when is_binary(value), do: String.slice(value, 0, 120)
  defp route_label(_), do: "Unavailable label"

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
         :ok <- expected_route(route, Keyword.get(opts, :expected_route)),
         {:ok, starts_at} <- parse_time(window, :starts_at),
         {:ok, ends_at} <- parse_time(window, :ends_at),
         {starts_at, ends_at} = whole_seconds(starts_at, ends_at),
         :ok <- validate_window(starts_at, ends_at, opts),
         result_limit = result_limit(opts),
         {:ok, response} <-
           ProviderControl.search_opportunities(
             organization_id,
             mission_id,
             route.provider_id,
             %{
               "spacecraft_refs" => [route.provider_spacecraft_ref],
               "ground_station_refs" => [],
               "service_profile_ref" => route.service_profile_ref["id"],
               "starts_at" => DateTime.to_iso8601(starts_at),
               "ends_at" => DateTime.to_iso8601(ends_at),
               "page_size" => result_limit,
               "cursor" => nil
             },
             Keyword.put(opts, :provider_version, route.provider_version)
           ),
         result <- search_result(response, route, starts_at, ends_at, result_limit) do
      result
    else
      false -> {:error, :spacecraft_required}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def search_result(response, route, starts_at, ends_at, result_limit) do
    with {:ok, opportunities} <-
           validate_opportunities(response, route, starts_at, ends_at, result_limit) do
      {:ok,
       %{
         route: route,
         truncated:
           Map.get(response, :truncated, Map.get(response, "truncated", false)) == true or
             not is_nil(Map.get(response, :next_cursor, Map.get(response, "next_cursor"))),
         provider_evidence:
           response
           |> Map.get(:provider_evidence, Map.get(response, "provider_evidence", %{}))
           |> Validation.sanitize(),
         opportunities:
           Enum.map(opportunities, fn opportunity ->
             opportunity
             |> Map.put("route_key", route.route_key)
             |> Map.put("delivery_profile_ref", route.delivery_profile_ref["id"])
           end)
       }}
    end
  end

  defp expected_route(_, nil), do: :ok

  defp expected_route(route, expected) do
    if route_evidence(route) === expected, do: :ok, else: {:error, :route_changed}
  end

  defp resolve_rules(spacecraft, [], _rules, _pins) do
    {[],
     [
       finding(
         :missing_source_endpoint,
         "Spacecraft needs a provider spacecraft mapping before contacts can be scheduled.",
         spacecraft.spacecraft_id
       )
     ]}
  end

  defp resolve_rules(spacecraft, _endpoints, [], _pins) do
    {[],
     [
       finding(
         :missing_downlink_route,
         "Spacecraft needs an enabled inbound Routing Rule before contacts can be scheduled.",
         spacecraft.spacecraft_id
       )
     ]}
  end

  defp resolve_rules(spacecraft, endpoints, rules, pins) do
    Enum.reduce(rules, {[], []}, fn rule, {routes, findings} ->
      case resolve_rule(spacecraft, endpoints, rule, pins) do
        {:ok, route} ->
          {[route | routes], findings}

        {:error, code, message, resource_id} ->
          {routes, [finding(code, message, resource_id) | findings]}
      end
    end)
  end

  defp resolve_rule(spacecraft, endpoints, rule, pins) do
    with :ok <- current_transport_pin(rule, pins.current_transports),
         {:ok, assignment} <- downlink_assignment(rule, pins.assignments),
         {:ok, template} <-
           fetch_pin(
             pins.templates,
             {assignment.path_template_id, assignment.path_template_version},
             :contact_path_template_not_found
           ),
         {:ok, endpoint} <- source_endpoint(endpoints, assignment.source_endpoint_ref),
         :ok <- provider_spacecraft_mapping(endpoint),
         {:ok, transport} <-
           fetch_pin(
             pins.transports,
             {rule.transport_id, rule.transport_version},
             :transport_not_found
           ),
         :ok <- externally_schedulable_transport(transport),
         provider_key = {transport.mission_provider_id, transport.mission_provider_version},
         {:ok, provider} <- fetch_pin(pins.providers, provider_key, :mission_provider_not_found),
         :ok <- Map.fetch!(pins.provider_readiness, provider_key),
         {:ok, service_profile} <-
           exact_profile(provider, "service_profiles", transport.service_profile_ref),
         {:ok, delivery_profile} <-
           exact_profile(provider, "delivery_profiles", transport.delivery_profile_ref),
         :ok <- profiles_compatible(service_profile, delivery_profile),
         :ok <- transport_snapshot_matches(transport, provider, service_profile, delivery_profile),
         {:ok, runtime_profile} <- runtime_profile(transport, pins.profiles),
         :ok <- runtime_profile_pin(runtime_profile, assignment, template),
         {:ok, context} <- ProviderContext.from_mission_provider(provider),
         {:ok, client} <- Registry.fetch(context) do
      {:ok,
       ready_route(%{
         spacecraft: spacecraft,
         endpoint: endpoint,
         rule: rule,
         assignment: assignment,
         template: template,
         transport: transport,
         provider: provider,
         runtime_profile: runtime_profile,
         service_profile: service_profile,
         delivery_profile: delivery_profile,
         client: client
       })}
    else
      {:error, :contact_link_assignment_not_found} ->
        route_error(
          :missing_downlink_path,
          "Routing Rule has no materialized downlink path.",
          rule
        )

      {:error, :contact_path_template_not_found} ->
        route_error(:missing_downlink_path, "Routing Rule path version is unavailable.", rule)

      {:error, :source_endpoint_not_found} ->
        route_error(
          :missing_source_endpoint,
          "Routing Rule source endpoint is unavailable.",
          rule
        )

      {:error, :transport_not_found} ->
        route_error(
          :missing_transport_version,
          "Routing Rule Transport version is unavailable.",
          rule
        )

      {:error, code, message} ->
        route_error(code, message, rule)

      {:error, reason} ->
        route_error(:provider_route_not_ready, readiness_message(reason), rule)
    end
  end

  defp current_transport_pin(rule, pins) do
    case Map.get(pins, rule.transport_id) do
      nil ->
        {:error, :transport_not_found}

      {_version, state} when state != "active" ->
        {:error, :transport_archived, "The Transport is archived."}

      {version, "active"} when version == rule.transport_version ->
        :ok

      {_version, "active"} ->
        {:error, :transport_version_changed,
         "The Routing Rule has not reached the current Transport version."}
    end
  end

  defp runtime_profile_pin(profile, assignment, template) do
    ref = %{"provider_profile_id" => profile.provider_profile_id, "version" => profile.version}

    if ref in template.provider_profile_refs and
         (assignment.provider_profile_refs == [] or ref in assignment.provider_profile_refs),
       do: :ok,
       else: {:error, :transport_runtime_profile_mismatch}
  end

  defp downlink_rule?(%RoutingRule{} = rule) do
    rule.lifecycle_state == :active and rule.enabled? and
      rule.direction in [:inbound, :bidirectional]
  end

  defp downlink_assignment(rule, assignments) do
    rule
    |> RoutePins.materialized_assignment_ids()
    |> Enum.reduce_while({:error, :contact_link_assignment_not_found}, fn assignment_id, _acc ->
      case Map.get(assignments, assignment_id) do
        %LinkAssignment{direction: :downlink} = assignment ->
          {:halt, {:ok, assignment}}

        _other ->
          {:cont, {:error, :contact_link_assignment_not_found}}
      end
    end)
  end

  defp fetch_pin(pins, key, reason) do
    case Map.fetch(pins, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, reason}
    end
  end

  defp source_endpoint(endpoints, source_endpoint_id) do
    assigned = Enum.find(endpoints, &(&1.source_endpoint_id == source_endpoint_id))
    mapped = Enum.find(endpoints, &present?(&1.source_ref))

    case mapped || assigned do
      %SourceEndpoint{} = endpoint -> {:ok, endpoint}
      nil -> {:error, :source_endpoint_not_found}
    end
  end

  defp provider_spacecraft_mapping(%SourceEndpoint{source_ref: source_ref}) do
    if present?(source_ref),
      do: :ok,
      else:
        {:error, :missing_provider_spacecraft_reference,
         "Source endpoint needs a provider spacecraft reference."}
  end

  defp externally_schedulable_transport(%Transport{
         origin: :provider_managed,
         lifecycle_state: :active
       }),
       do: :ok

  defp externally_schedulable_transport(%Transport{origin: :direct}) do
    {:error, :direct_transport_not_provider_schedulable,
     "Direct Transport remains available for local scheduling but has no external opportunity source."}
  end

  defp externally_schedulable_transport(%Transport{}) do
    {:error, :transport_not_active, "Selected Transport version is not active."}
  end

  defp exact_profile(provider, collection, reference) do
    with {:ok, id, version} <- profile_reference(reference),
         items when is_list(items) <-
           get_in(provider.inventory_sync_document, [collection, "items"]),
         profile when is_map(profile) <-
           Enum.find(items, &(&1["id"] == id and &1["version"] == version)) do
      {:ok, profile}
    else
      _other -> {:error, :provider_profile_version_not_available}
    end
  end

  defp profile_reference(reference) when is_map(reference) do
    id = Map.get(reference, "id", Map.get(reference, :id))
    version = Map.get(reference, "version", Map.get(reference, :version))

    if present?(id) and is_integer(version) and version > 0,
      do: {:ok, id, version},
      else: {:error, :invalid_provider_profile_reference}
  end

  defp profile_reference(_reference), do: {:error, :invalid_provider_profile_reference}

  defp profiles_compatible(service_profile, delivery_profile) do
    cond do
      service_profile["state"] != "active" ->
        {:error, :provider_service_profile_not_active}

      delivery_profile["state"] != "ready" ->
        {:error, :provider_delivery_profile_not_ready}

      service_profile["direction"] != "downlink" or delivery_profile["direction"] != "downlink" ->
        {:error, :provider_profile_direction_not_supported}

      service_profile["id"] not in (delivery_profile["supported_service_profile_refs"] || []) ->
        {:error, :provider_profiles_not_compatible}

      true ->
        :ok
    end
  end

  defp transport_snapshot_matches(transport, provider, service_profile, delivery_profile) do
    snapshot = transport.provider_configuration_snapshot

    if get_in(snapshot, ["provider", "id"]) == provider.provider_id and
         get_in(snapshot, ["provider", "version"]) == provider.version and
         get_in(snapshot, ["service_profile", "id"]) == service_profile["id"] and
         get_in(snapshot, ["service_profile", "version"]) == service_profile["version"] and
         get_in(snapshot, ["delivery_profile", "id"]) == delivery_profile["id"] and
         get_in(snapshot, ["delivery_profile", "version"]) == delivery_profile["version"] do
      :ok
    else
      {:error, :transport_provider_snapshot_mismatch}
    end
  end

  defp runtime_profile(%Transport{materialized_provider_profile_id: id} = transport, profiles)
       when is_binary(id) and id != "" do
    with {:ok, profile} <- Map.fetch(profiles, id),
         true <- profile.metadata["materialized_from_transport_id"] == transport.transport_id,
         true <- profile.metadata["materialized_from_transport_version"] == transport.version do
      {:ok, profile}
    else
      _other -> {:error, :transport_runtime_profile_mismatch}
    end
  end

  defp runtime_profile(_transport, _profiles),
    do: {:error, :transport_runtime_profile_not_materialized}

  defp ready_route(%{
         spacecraft: spacecraft,
         endpoint: endpoint,
         rule: rule,
         assignment: assignment,
         template: template,
         transport: transport,
         provider: provider,
         runtime_profile: runtime_profile,
         service_profile: service_profile,
         delivery_profile: delivery_profile,
         client: client
       }) do
    route_key =
      [
        spacecraft.spacecraft_id,
        rule.routing_rule_id,
        transport.transport_id,
        transport.version,
        provider.provider_id,
        provider.version,
        service_profile["id"],
        service_profile["version"],
        delivery_profile["id"],
        delivery_profile["version"]
      ]
      |> Enum.join(":")

    %{
      route_key: route_key,
      spacecraft_id: spacecraft.spacecraft_id,
      spacecraft_display_name: spacecraft.display_name,
      provider_spacecraft_ref: endpoint.source_ref,
      source_endpoint_id: assignment.source_endpoint_ref,
      routing_rule_id: rule.routing_rule_id,
      link_assignment_id: assignment.link_assignment_id,
      path_template_id: template.path_template_id,
      path_template_version: template.version,
      transport_id: transport.transport_id,
      transport_version: transport.version,
      transport_display_name: transport.display_name,
      provider_id: provider.provider_id,
      provider_version: provider.version,
      provider_account_id: provider.provider_account_id,
      provider_account_version: provider.provider_account_version,
      provider_account_grant_id: provider.provider_account_grant_id,
      provider_account_grant_version: provider.provider_account_grant_version,
      provider_profile_id: runtime_profile.provider_profile_id,
      provider_profile_version: runtime_profile.version,
      service_profile_ref: exact_profile_ref(service_profile),
      delivery_profile_ref: exact_profile_ref(delivery_profile),
      delivery_policy_document: provider.delivery_policy_document,
      provider_display_name: provider.display_name,
      service_display_name: service_profile["display_name"] || service_profile["id"],
      delivery_display_name: delivery_profile["display_name"] || delivery_profile["id"],
      delivery_operator_summary:
        delivery_profile["operator_summary"] || delivery_profile["display_name"],
      route_display_name: rule.display_name,
      client: client
    }
  end

  defp exact_profile_ref(profile),
    do: %{"id" => profile["id"], "version" => profile["version"]}

  defp route_error(code, message, rule),
    do: {:error, code, message, rule.routing_rule_id}

  defp readiness_message(:mission_provider_not_found),
    do: "Bound Mission Provider version is unavailable."

  defp readiness_message(:provider_profile_version_not_available),
    do: "Bound provider profile version is unavailable."

  defp readiness_message(:provider_service_profile_not_active),
    do: "Bound Service Profile is not active."

  defp readiness_message(:provider_delivery_profile_not_ready),
    do: "Bound Delivery Profile is not ready."

  defp readiness_message(:provider_profiles_not_compatible),
    do: "Bound Service and Delivery Profiles are not compatible."

  defp readiness_message(:transport_provider_snapshot_mismatch),
    do: "Transport provider snapshot does not match its exact bindings."

  defp readiness_message(:transport_runtime_profile_mismatch),
    do: "Transport runtime materialization does not match the selected version."

  defp readiness_message(:transport_runtime_profile_not_materialized),
    do: "Transport runtime compatibility profile is unavailable."

  defp readiness_message({:unknown_provider_client, _client}),
    do: "Mission Provider scheduling client is not supported."

  defp readiness_message(_reason), do: "Provider scheduling route is not ready."

  @doc false
  def validate_window(starts_at, ends_at, opts) do
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

  @doc false
  def result_limit(opts), do: Keyword.get(opts, :result_limit, @default_result_limit)

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
         true <- opportunity.service_profile_ref == route.service_profile_ref["id"],
         starts_at = opportunity.starts_at,
         ends_at = opportunity.ends_at,
         true <- DateTime.compare(starts_at, window_starts_at) in [:eq, :gt],
         true <- DateTime.compare(ends_at, window_ends_at) in [:eq, :lt] do
      {:ok, Opportunity.to_map(opportunity)}
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

  # Providers offer windows in whole seconds. The window sent and the bounds each offer is checked
  # against are the same whole-second window, the start rounded up and the end down, so an offer
  # that starts in the window's first second is inside it rather than a fraction of a second early.
  defp whole_seconds(starts_at, ends_at), do: {second_ceiling(starts_at), second_floor(ends_at)}

  defp second_floor(%DateTime{} = time), do: DateTime.truncate(time, :second)

  defp second_ceiling(%DateTime{microsecond: {0, _precision}} = time), do: second_floor(time)

  defp second_ceiling(%DateTime{} = time),
    do: time |> DateTime.add(1, :second) |> second_floor()

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

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
