defmodule Cadence.Management.CommunicationsSetup do
  @moduledoc """
  Authorized Communications setup workflows, independent of frontend delivery.

  This management-plane coordinator composes mission identity, Comms persistence
  and provider-backed transport configuration. The caller owns submission replay
  admission; these functions do not promise cross-session exactly-once effects.
  """
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore,
    Transport
  }

  alias Cadence.ExtensionCatalog
  alias Cadence.Management.{Providers, Transports}
  alias Cadence.Missions

  @forms ~w(transport_new routing_new ground_station_new ground_station_edit)

  def execute(%Scope{mission_id: scoped_mission} = scope, mission_id, form, event, input)
      when form in @forms and event in ["validate", "save"] and
             (is_nil(scoped_mission) or scoped_mission == mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         :ok <- bounded_input(input) do
      case event do
        "validate" -> validate_form(scope, mission_id, input, form)
        "save" -> save_form(scope, mission_id, input, form)
      end
    end
  end

  def execute(_scope, _mission_id, _form, _event, _input),
    do: {:error, :invalid_application_request}

  defp bounded_input(input) when is_map(input) and map_size(input) == 1 do
    case Map.to_list(input) do
      [{key, fields}]
      when key in ["transport", "routing_rule", "ground_station"] and is_map(fields) ->
        if map_size(fields) <= 64 and Enum.all?(fields, &bounded_field?/1),
          do: :ok,
          else: {:error, :invalid_application_request}

      _ ->
        {:error, :invalid_application_request}
    end
  end

  defp bounded_input(_input), do: {:error, :invalid_application_request}

  defp bounded_field?({key, value}),
    do:
      is_binary(key) and byte_size(key) <= 128 and String.valid?(key) and
        is_binary(value) and byte_size(value) <= 8192 and String.valid?(value)

  defp save_form(scope, mission_id, %{"transport" => params} = payload, "transport_new")
       when is_map(params) and map_size(payload) == 1 do
    with {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, transport} <- build_transport(scope, mission_id, params, display_name),
         {:ok, saved} <- Transports.persist_transport(scope.organization_id, transport) do
      href = "/missions/#{mission_id}/comms/transports/#{saved.transport_id}"
      {:ok, navigation_result("transportId", saved.transport_id, href)}
    end
  end

  defp save_form(scope, mission_id, %{"routing_rule" => params} = payload, "routing_new")
       when is_map(params) and map_size(payload) == 1 do
    with {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, purpose_label} <- required_text(params, "purpose_label"),
         {:ok, spacecraft_id} <- required_text(params, "spacecraft_id"),
         {:ok, transport_ref} <- transport_ref(params),
         {:ok, direction} <-
           known_value(params, "direction", ["inbound", "outbound", "bidirectional"]),
         {:ok, role} <- known_value(params, "role", ["primary", "candidate", "contributing"]),
         {:ok, saved} <-
           RoutingRuleStore.create_routing_rule(
             scope.organization_id,
             RoutingRule.new(%{
               mission_id: mission_id,
               spacecraft_id: spacecraft_id,
               display_name: display_name,
               purpose_label: purpose_label,
               direction: direction,
               transport_id: transport_ref.transport_id,
               transport_version: transport_ref.version,
               role: role,
               enabled?: true
             })
           ) do
      href = "/missions/#{mission_id}/comms/routing/#{saved.routing_rule_id}"
      {:ok, navigation_result("routingRuleId", saved.routing_rule_id, href)}
    end
  end

  defp save_form(scope, mission_id, %{"ground_station" => params} = payload, surface_id)
       when surface_id in ["ground_station_new", "ground_station_edit"] and
              is_map(params) and map_size(payload) == 1 do
    with {:ok, attrs} <- ground_station_attrs(params) do
      save_ground_station(scope, mission_id, attrs, surface_id)
    end
  end

  defp save_form(_scope, _mission_id, _params, _surface_id),
    do: {:error, :invalid_application_request}

  defp save_ground_station(
         scope,
         mission_id,
         %{ground_station_id: id} = attrs,
         "ground_station_new"
       ) do
    case GroundStationStore.fetch_ground_station(scope.organization_id, mission_id, id) do
      {:ok, _existing} -> {:error, :ground_station_already_exists}
      {:error, :ground_station_not_found} -> persist_ground_station(scope, mission_id, attrs)
    end
  end

  defp save_ground_station(
         scope,
         mission_id,
         %{ground_station_id: id} = attrs,
         "ground_station_edit"
       ) do
    with {:ok, _current} <-
           GroundStationStore.fetch_ground_station(scope.organization_id, mission_id, id),
         {:ok, saved} <-
           GroundStationStore.update_ground_station(
             scope.organization_id,
             mission_id,
             id,
             Map.delete(attrs, :ground_station_id)
           ) do
      href = "/missions/#{mission_id}/comms/ground-stations/#{saved.ground_station_id}"
      {:ok, navigation_result("groundStationId", saved.ground_station_id, href)}
    end
  end

  defp persist_ground_station(scope, mission_id, attrs) do
    with {:ok, saved} <-
           GroundStationStore.persist_ground_station(
             scope.organization_id,
             GroundStation.new(Map.put(attrs, :mission_id, mission_id))
           ) do
      href = "/missions/#{mission_id}/comms/ground-stations/#{saved.ground_station_id}"
      {:ok, navigation_result("groundStationId", saved.ground_station_id, href)}
    end
  end

  defp validate_form(
         scope,
         mission_id,
         %{"transport" => %{"origin" => "provider_managed"} = params} = payload,
         "transport_new"
       )
       when map_size(payload) == 1 do
    with {:ok, entry} <- ExtensionCatalog.fetch_transport_kind(params["transport_kind"]),
         {:ok, selection} <- provider_selection(scope, mission_id, entry, params) do
      configuration = selection.configuration
      summary = if configuration, do: entry.module.display_summary(configuration)

      result = %{
        "valid" =>
          match?({:ok, _}, required_text(params, "display_name")) and not is_nil(configuration),
        "transport_review" => %{
          "origin" => "provider_managed",
          "endpoint" => if(summary, do: summary.endpoint)
        },
        "provider_setup" => %{
          "version" => 1,
          "transport_kind" => params["transport_kind"],
          "provider_id" => params["mission_provider_id"] || "",
          "provider_version" => params["mission_provider_version"] || "",
          "service_profile_id" => params["service_profile_id"] || "",
          "delivery_profile_id" => params["delivery_profile_id"] || "",
          "provider_name" => if(selection.provider, do: selection.provider.display_name),
          "services" => Enum.map(selection.services, &profile_option/1),
          "deliveries" => Enum.map(selection.deliveries, &profile_option/1),
          "configuration" => provider_configuration_rows(configuration, summary)
        }
      }

      with :ok <- JSONBoundary.validate(result), do: {:ok, result}
    end
  end

  defp validate_form(scope, mission_id, %{"transport" => params} = payload, "transport_new")
       when is_map(params) and map_size(payload) == 1 do
    with {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, transport} <- build_transport(scope, mission_id, params, display_name),
         {:ok, entry} <- ExtensionCatalog.fetch_transport_kind(params["transport_kind"]) do
      summary = entry.module.display_summary(transport.configuration)

      {:ok,
       %{
         "valid" => true,
         "transport_review" => %{
           "origin" => Atom.to_string(transport.origin),
           "endpoint" => summary.endpoint
         }
       }}
    end
  end

  defp validate_form(_scope, _mission_id, params, surface_id) do
    with :ok <- validate_form_for_surface(params, surface_id) do
      {:ok, %{"valid" => true}}
    end
  end

  defp validate_form_for_surface(
         %{"routing_rule" => params} = payload,
         "routing_new"
       )
       when is_map(params) and map_size(payload) == 1 do
    with {:ok, _display_name} <- required_text(params, "display_name"),
         {:ok, _purpose} <- required_text(params, "purpose_label"),
         {:ok, _spacecraft} <- required_text(params, "spacecraft_id"),
         {:ok, _transport} <- transport_ref(params),
         {:ok, _direction} <-
           known_value(params, "direction", ["inbound", "outbound", "bidirectional"]),
         {:ok, _role} <- known_value(params, "role", ["primary", "candidate", "contributing"]) do
      :ok
    end
  end

  defp validate_form_for_surface(
         %{"ground_station" => params} = payload,
         surface_id
       )
       when surface_id in ["ground_station_new", "ground_station_edit"] and
              is_map(params) and map_size(payload) == 1 do
    with {:ok, _attrs} <- ground_station_attrs(params) do
      :ok
    end
  end

  defp validate_form_for_surface(_params, _surface_id),
    do: {:error, :invalid_application_request}

  defp navigation_result(resource_key, resource_id, href) do
    %{
      resource_key => resource_id,
      "href" => href,
      "redirect" => href,
      "navigation" => %{"kind" => "navigate", "href" => href}
    }
  end

  defp build_transport(_scope, mission_id, %{"origin" => "direct"} = params, display_name) do
    with {:ok, entry} <-
           ExtensionCatalog.fetch_transport_kind(Map.get(params, "transport_kind", "tcp_socket")),
         {:ok, configuration} <- entry.module.normalize_config(direct_config_params(params)) do
      {:ok,
       Transport.new(%{
         mission_id: mission_id,
         display_name: display_name,
         origin: :direct,
         transport_kind: entry.kind,
         adapter_key: entry.adapter_key,
         direction_capability: configuration["direction_capability"],
         configuration: configuration
       })}
    end
  end

  defp build_transport(
         scope,
         mission_id,
         %{"origin" => "provider_managed"} = params,
         display_name
       ) do
    with {:ok, entry} <-
           ExtensionCatalog.fetch_transport_kind(Map.get(params, "transport_kind", "tcp_socket")),
         {:ok, selection} <- provider_selection(scope, mission_id, entry, params),
         %{} = configuration <- selection.configuration do
      %{provider: provider, service: service, delivery: delivery} = selection

      {:ok,
       Transport.new(%{
         mission_id: mission_id,
         display_name: display_name,
         origin: :provider_managed,
         transport_kind: entry.kind,
         adapter_key: entry.adapter_key,
         direction_capability: configuration["direction_capability"],
         configuration: configuration,
         mission_provider_id: provider.provider_id,
         mission_provider_version: provider.version,
         service_profile_ref: profile_ref(service),
         delivery_profile_ref: profile_ref(delivery)
       })}
    else
      nil -> {:error, :provider_managed_transport_selection_incomplete}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_transport(_scope, _mission_id, _params, _display_name),
    do: {:error, :invalid_transport_origin}

  defp direct_config_params(params) do
    %{
      "mode" => params["tcp_mode"],
      "direction_capability" => params["direction_capability"],
      "host" => params["host"],
      "port" => params["port"],
      "framing_mode" => params["framing_mode"],
      "frame_size" => params["frame_size"],
      "reconnect_policy" => params["reconnect_policy"],
      "tls_enabled" => params["tls_enabled"]
    }
  end

  defp profile_items(provider, key) do
    case get_in(provider.inventory_sync_document, [key, "items"]) do
      items when is_list(items) -> items
      _other -> []
    end
  end

  defp provider_selection(scope, mission_id, entry, params) do
    providers = Providers.list_providers(scope.organization_id, mission_id)

    with true <-
           Enum.all?(
             ~w(mission_provider_id mission_provider_version service_profile_id delivery_profile_id),
             &is_binary(params[&1])
           ),
         {:ok, provider} <-
           optional_selection(providers, params["mission_provider_id"], & &1.provider_id),
         true <- not is_nil(provider) or params["mission_provider_version"] == "",
         true <-
           is_nil(provider) or
             (provider_ready?(provider) and
                params["mission_provider_version"] == Integer.to_string(provider.version)),
         services <-
           if(provider,
             do:
               Enum.filter(
                 profile_items(provider, "service_profiles"),
                 &(&1["state"] == "active" and &1["direction"] == "downlink")
               ),
             else: []
           ),
         {:ok, service} <-
           optional_selection(services, params["service_profile_id"], &profile_token/1),
         deliveries <- if(service, do: compatible_deliveries(provider, service, entry), else: []),
         {:ok, delivery} <-
           optional_selection(deliveries, params["delivery_profile_id"], &profile_token/1),
         {:ok, configuration} <-
           if(delivery, do: entry.module.from_delivery_profile(delivery), else: {:ok, nil}) do
      {:ok,
       %{
         provider: provider,
         services: services,
         service: service,
         deliveries: deliveries,
         delivery: delivery,
         configuration: configuration
       }}
    else
      false -> {:error, :mission_provider_not_validated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp optional_selection(_items, token, _identity) when token in [nil, ""], do: {:ok, nil}

  defp optional_selection(items, token, identity) do
    case Enum.filter(items, &(identity.(&1) == token)) do
      [item] -> {:ok, item}
      _other -> {:error, :provider_managed_transport_selection_incomplete}
    end
  end

  defp profile_option(profile) do
    %{
      "label" => "#{profile["display_name"] || profile["id"]} · v#{profile["version"]}",
      "value" => profile_token(profile),
      "disabled" => false
    }
  end

  defp provider_configuration_rows(nil, _summary), do: []

  defp provider_configuration_rows(configuration, summary) do
    [
      {"Endpoint", summary.endpoint},
      {"Mode", summary.mode},
      {"Direction", summary.direction_capability},
      {"Framing", summary.framing},
      {"Frame bytes", configuration["fixed_message_bytes"] || "Not fixed"},
      {"Reconnect", get_in(configuration, ["reconnect", "policy"]) || "Not configured"},
      {"TLS", if(summary.tls_enabled?, do: "Enabled", else: "Disabled")}
    ]
    |> Enum.map(fn {label, value} ->
      %{"label" => label, "value" => to_string(value), "mono" => true}
    end)
  end

  defp compatible_deliveries(provider, service, kind_entry) do
    provider
    |> profile_items("delivery_profiles")
    |> Enum.filter(fn delivery ->
      delivery["state"] == "ready" and delivery["direction"] == "downlink" and
        service["id"] in (delivery["supported_service_profile_refs"] || []) and
        match?({:ok, _}, kind_entry.module.from_delivery_profile(delivery))
    end)
  end

  defp profile_token(profile),
    do:
      profile
      |> Map.take(["id", "version"])
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

  defp profile_ref(profile), do: Map.take(profile, ["id", "version"])

  defp provider_ready?(provider),
    do:
      provider.lifecycle_state == :active and match?(%DateTime{}, provider.last_validated_at) and
        match?(%DateTime{}, provider.last_synced_at) and
        get_in(provider.metadata, ["control_plane", "status"]) == "healthy"

  defp transport_ref(%{"transport_ref" => value}) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [transport_id, version] when transport_id != "" ->
        case Integer.parse(version) do
          {version, ""} when version > 0 -> {:ok, %{transport_id: transport_id, version: version}}
          _other -> {:error, :invalid_application_request}
        end

      _other ->
        {:error, :invalid_application_request}
    end
  end

  defp transport_ref(_params), do: {:error, :invalid_application_request}

  defp known_value(params, key, allowed) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        if value in allowed, do: {:ok, value}, else: {:error, :invalid_application_request}

      _other ->
        {:error, :invalid_application_request}
    end
  end

  defp ground_station_attrs(params) do
    with {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, ground_station_id} <- ground_station_id(params),
         {:ok, metadata} <- parse_metadata(params["metadata_json"]) do
      {:ok,
       %{
         ground_station_id: ground_station_id,
         display_name: display_name,
         provider: optional_text(params["provider"]),
         region: optional_text(params["region"]),
         metadata: metadata
       }}
    end
  end

  defp ground_station_id(params) do
    case required_text(params, "ground_station_id") do
      {:ok, value} ->
        if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/, value),
          do: {:ok, value},
          else: {:error, :invalid_application_request}

      error ->
        error
    end
  end

  defp parse_metadata(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      _other -> {:error, :invalid_application_request}
    end
  end

  defp parse_metadata(_value), do: {:error, :invalid_application_request}

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp optional_text(_value), do: nil

  defp required_text(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_action_parameter, key}}
          value -> {:ok, value}
        end

      _invalid ->
        {:error, {:missing_action_parameter, key}}
    end
  end
end
