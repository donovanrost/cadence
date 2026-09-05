defmodule Cadence.Applications.Comms.ActionProvider do
  @moduledoc "Typed action adapter for mission Comms provider operations."

  # ActionRequest currently has no surface_id field.  The optional lookup below
  # is deliberately fail-closed when that field is composed into the host: it
  # then binds the shared validate/save IDs to the declared form surface.

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Auth.Scope

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore,
    Transport
  }

  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.ExtensionCatalog
  alias Cadence.GroundNetworks.{MissionProvider, ProviderAccountGrants, ProviderAccounts}
  alias Cadence.Management.Providers
  alias Cadence.Management.Transports
  alias Cadence.Missions

  @application_key "comms"

  @impl true
  def application_key, do: @application_key

  def execute(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: "validate",
          params: params
        } = request
      ) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         :ok <- validate_form(params, request_surface_id(request)) do
      {:ok, %{"valid" => true}}
    end
  end

  def execute(
        %Scope{organization_id: organization_id} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: "save",
          params: params
        } = request
      ) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id) do
      save_form(scope, mission_id, params, request_surface_id(request))
    end
  end

  @impl true
  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: action_id,
          params: params
        }
      )
      when action_id in ["validate_provider", "sync_provider", "archive_provider"] do
    with {:ok, provider_id} <- required_id(params, "provider_id") do
      case action_id do
        "validate_provider" -> ControlProviders.validate_current(scope, mission_id, provider_id)
        "sync_provider" -> ControlProviders.sync_current(scope, mission_id, provider_id)
        "archive_provider" -> Providers.archive_provider(scope, mission_id, provider_id)
      end
    end
  end

  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: "create_provider",
          params: params
        }
      ) do
    create_provider(scope, mission_id, provider_params(params))
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  @impl true
  def result(%MissionProvider{} = provider) do
    %{
      "provider_id" => provider.provider_id,
      "version" => provider.version,
      "display_name" => provider.display_name
    }
  end

  def result(value) when is_map(value), do: value
  def result(value), do: value

  defp create_provider(scope, mission_id, params) do
    with {:ok, grant_id} <- required_id(params, "provider_account_grant_id"),
         {:ok, grant} <-
           ProviderAccountGrants.fetch_active_for_system(scope.organization_id, grant_id),
         true <- grant.mission_id == mission_id,
         {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             scope.organization_id,
             grant.provider_account_id,
             grant.provider_account_version
           ),
         :ok <- immutable_account_id(params, grant.provider_account_id),
         {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, delivery_policy} <- delivery_policy(params) do
      provider =
        MissionProvider.new(%{
          mission_id: mission_id,
          display_name: display_name,
          provider_account_id: account_version.provider_account_id,
          provider_account_version: account_version.version,
          provider_account_grant_id: grant.provider_account_grant_id,
          provider_account_grant_version: grant.version,
          provider_type: account_version.provider_type,
          client_key: account_version.client_key,
          base_url: account_version.base_url,
          credential_ref: account_version.credential_ref,
          environment_ref: account_version.environment_ref,
          permitted_resource_refs: comma_list(Map.get(params, "permitted_resource_refs")),
          delivery_policy_document: delivery_policy
        })

      Providers.persist_provider(scope, provider)
    else
      false -> {:error, :provider_account_grant_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp save_form(scope, mission_id, %{"transport" => params}, surface_id)
       when is_map(params) do
    with :ok <- surface_payload_type(surface_id, "transport_new"),
         {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, transport} <- build_transport(scope, mission_id, params, display_name),
         {:ok, saved} <- Transports.persist_transport(scope.organization_id, transport) do
      href = "/missions/#{mission_id}/comms/transports/#{saved.transport_id}"
      {:ok, navigation_result("transportId", saved.transport_id, href)}
    end
  end

  defp save_form(scope, mission_id, %{"routing_rule" => params}, surface_id)
       when is_map(params) do
    with :ok <- surface_payload_type(surface_id, "routing_new"),
         {:ok, display_name} <- required_text(params, "display_name"),
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

  defp save_form(scope, mission_id, %{"ground_station" => params}, surface_id)
       when is_map(params) do
    with :ok <- surface_payload_type(surface_id, "ground_station_form"),
         {:ok, attrs} <- ground_station_attrs(params) do
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
      {:error, reason} -> {:error, reason}
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

  defp save_ground_station(scope, mission_id, attrs, nil),
    do: save_ground_station_legacy(scope, mission_id, attrs)

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

  defp save_ground_station_legacy(scope, mission_id, %{ground_station_id: id} = attrs) do
    case Cadence.Comms.GroundStationStore.fetch_ground_station(
           scope.organization_id,
           mission_id,
           id
         ) do
      {:ok, _current} ->
        with {:ok, saved} <-
               GroundStationStore.update_ground_station(
                 scope.organization_id,
                 mission_id,
                 id,
                 Map.delete(attrs, :ground_station_id)
               ) do
          href = "/missions/#{mission_id}/comms/ground-stations/#{saved.ground_station_id}"
          {:ok, navigation_result("groundStationId", saved.ground_station_id, href)}
        end

      {:error, :ground_station_not_found} ->
        persist_ground_station(scope, mission_id, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp surface_payload_type(nil, _expected), do: :ok
  defp surface_payload_type("transport_new", "transport_new"), do: :ok
  defp surface_payload_type("routing_new", "routing_new"), do: :ok

  defp surface_payload_type(surface_id, "ground_station_form")
       when surface_id in ["ground_station_new", "ground_station_edit"],
       do: :ok

  defp surface_payload_type(_surface_id, _expected), do: {:error, :invalid_application_request}

  defp validate_form(params, surface_id) do
    validate_form_for_surface(params, surface_id)
  end

  defp request_surface_id(%ActionRequest{} = request),
    do: Map.get(Map.from_struct(request), :surface_id)

  defp validate_form_for_surface(%{"transport" => params}, surface_id) when is_map(params) do
    with :ok <- surface_payload_type(surface_id, "transport_new"),
         {:ok, _display_name} <- required_text(params, "display_name"),
         {:ok, _kind} <-
           ExtensionCatalog.fetch_transport_kind(Map.get(params, "transport_kind", "tcp_socket")) do
      :ok
    end
  end

  defp validate_form_for_surface(%{"routing_rule" => params}, surface_id) when is_map(params) do
    with :ok <- surface_payload_type(surface_id, "routing_new"),
         {:ok, _display_name} <- required_text(params, "display_name"),
         {:ok, _purpose} <- required_text(params, "purpose_label"),
         {:ok, _spacecraft} <- required_text(params, "spacecraft_id"),
         {:ok, _transport} <- transport_ref(params),
         {:ok, _direction} <-
           known_value(params, "direction", ["inbound", "outbound", "bidirectional"]),
         {:ok, _role} <- known_value(params, "role", ["primary", "candidate", "contributing"]) do
      :ok
    end
  end

  defp validate_form_for_surface(%{"ground_station" => params}, surface_id)
       when is_map(params) do
    with :ok <- surface_payload_type(surface_id, "ground_station_form"),
         {:ok, _attrs} <- ground_station_attrs(params) do
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
    providers = Providers.list_providers(scope.organization_id, mission_id)

    with {:ok, entry} <-
           ExtensionCatalog.fetch_transport_kind(Map.get(params, "transport_kind", "tcp_socket")),
         %{} = provider <- select_provider(providers, Map.get(params, "mission_provider_id")),
         true <- provider_ready?(provider),
         %{} = service <-
           select_profile(
             profile_items(provider, "service_profiles"),
             Map.get(params, "service_profile_id")
           ),
         %{} = delivery <-
           select_profile(
             compatible_deliveries(provider, service, entry),
             Map.get(params, "delivery_profile_id")
           ),
         {:ok, configuration} <- entry.module.from_delivery_profile(delivery) do
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
      false -> {:error, :mission_provider_not_validated}
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

  defp select_provider(providers, provider_id),
    do: Enum.find(providers, &(&1.provider_id == provider_id))

  defp select_profile(profiles, token) do
    Enum.find(profiles, fn profile -> profile_token(profile) == token end)
  end

  defp compatible_deliveries(provider, service, kind_entry) do
    provider
    |> profile_items("delivery_profiles")
    |> Enum.filter(fn delivery ->
      delivery["state"] == "ready" and
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
      match?(%DateTime{}, provider.last_validated_at) and
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

  defp provider_params(params) when is_map(params), do: Map.get(params, "provider", params)
  defp provider_params(_params), do: %{}

  defp immutable_account_id(params, account_id) do
    case Map.get(params, "provider_account_id") do
      nil -> :ok
      ^account_id -> :ok
      _other -> {:error, :provider_account_binding_mismatch}
    end
  end

  defp delivery_policy(%{"policy_mode" => "approval_required"} = params) do
    {:ok,
     %{
       "mode" => "approval_required",
       "changes_always_requiring_approval" => ["schedule", "resource", "capacity", "cost"],
       "deadline_behavior" => Map.get(params, "deadline_behavior", "retain_last_accepted")
     }}
  end

  defp delivery_policy(%{"policy_mode" => "bounded_automatic"} = params) do
    {:ok,
     %{
       "mode" => "bounded_automatic",
       "deadline_behavior" => Map.get(params, "deadline_behavior", "retain_last_accepted"),
       "approved_station_substitutions" =>
         comma_list(Map.get(params, "approved_station_substitutions"))
     }}
  end

  defp delivery_policy(_params), do: {:error, :invalid_delivery_policy}

  defp required_id(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:missing_action_parameter, key}}
    end
  end

  defp required_id(_params, key), do: {:error, {:missing_action_parameter, key}}

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

  defp comma_list(value) when is_binary(value),
    do: value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp comma_list(_value), do: []
end
