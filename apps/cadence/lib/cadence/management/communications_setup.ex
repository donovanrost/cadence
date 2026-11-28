defmodule Cadence.Management.CommunicationsSetup do
  @moduledoc """
  Authorized Communications setup workflows, independent of frontend delivery.

  This management-plane coordinator composes mission identity and Comms persistence for the
  routing and ground-station forms. Transports are written only through the console's change
  sets; the old `transport_new` form was removed (#990), so no path here creates a listening
  transport outside the kind's allowlist rule. The caller owns submission replay admission;
  these functions do not promise cross-session exactly-once effects.
  """
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore
  }

  alias Cadence.Missions

  @forms ~w(routing_new ground_station_new ground_station_edit)

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
      when key in ["routing_rule", "ground_station"] and is_map(fields) ->
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
