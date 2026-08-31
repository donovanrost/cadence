defmodule CadenceWeb.ApplicationHostBridge do
  @moduledoc "Canonical JSON bridge for registry-admitted federated application surfaces."

  alias Cadence.Applications.{
    ActionDefinition,
    ActionDispatcher,
    ActionRequest,
    ApplicationDefinition,
    SurfaceDefinition,
    SurfaceDocument
  }

  alias Cadence.Applications.HostQueryRegistry
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces
  alias CadenceWeb.ApplicationHostCatalog
  alias CadenceWeb.ApplicationSurfaces.{Declarative, DocumentState}

  @max_json_depth 8
  @max_json_items 100
  @max_json_text_bytes 240
  @max_json_integer 9_007_199_254_740_991
  @min_json_integer -9_007_199_254_740_991

  @type route_context :: ApplicationHostCatalog.route_context()

  @spec query(Scope.t(), route_context(), map()) :: {:ok, map()} | {:error, term()}
  def query(%Scope{} = current_scope, route_context, params) when is_map(params) do
    case HostQueryRegistry.dispatch(current_scope, route_context, params) do
      :not_handled -> generic_query(current_scope, route_context, params)
      result -> result
    end
  end

  def query(%Scope{}, _route_context, _params), do: {:error, :invalid_application_request}

  @spec action(Scope.t(), route_context(), map(), binary()) ::
          {:ok, map()} | {:error, term()}
  def action(
        %Scope{} = current_scope,
        route_context,
        params,
        idempotency_key
      )
      when is_map(params) and is_binary(idempotency_key) and
             byte_size(idempotency_key) <= @max_json_text_bytes and idempotency_key != "" do
    if String.valid?(idempotency_key) and Map.has_key?(params, "surfaceId") do
      generic_action(current_scope, route_context, params, idempotency_key)
    else
      {:error, :unsupported_application_action}
    end
  end

  def action(%Scope{}, _route_context, _params, _idempotency_key),
    do: {:error, :invalid_application_request}

  defp generic_query(current_scope, route_context, params) do
    with {:ok, request} <- query_request(params),
         {:ok, admission} <- admit_surface(current_scope, route_context, request),
         :ok <- ensure_query_contract(admission, request),
         {:ok, document} <-
           ApplicationSurfaces.load(
             current_scope,
             route_context.host_context,
             admission.definition.application_key,
             admission.definition.version,
             admission.surface,
             request.params
           ) do
      query_response(admission, document)
    end
  end

  defp generic_action(current_scope, route_context, params, idempotency_key) do
    with {:ok, request} <- action_request(params, idempotency_key),
         {:ok, admission} <- admit_surface(current_scope, route_context, request),
         {:ok, action} <- declared_action(admission, request),
         {:ok, result} <-
           ActionDispatcher.dispatch(
             current_scope,
             route_context.host_context,
             %ActionRequest{
               application_key: admission.definition.application_key,
               application_version: admission.definition.version,
               action_id: action.action_id,
               params: request.params,
               idempotency_key: idempotency_key
             }
           ) do
      {:ok,
       %{
         "receiptId" => receipt_id(idempotency_key),
         "completedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "result" => json_safe(ActionDispatcher.result(request.application_key, result))
       }}
    end
  end

  defp query_request(params) do
    with {:ok, application_key} <- required_text(params, "applicationKey"),
         {:ok, application_version} <- positive_integer(params, "applicationVersion"),
         {:ok, surface_id} <- required_text(params, "surfaceId"),
         {:ok, surface_version} <- positive_integer(params, "surfaceVersion"),
         {:ok, query_id} <- required_text(params, "queryId"),
         {:ok, query_version} <- query_version(params),
         {:ok, query_params} <- optional_map(params, "params") do
      {:ok,
       %{
         application_key: application_key,
         application_version: application_version,
         surface_id: surface_id,
         surface_version: surface_version,
         query_id: query_id,
         query_version: query_version,
         params: query_params
       }}
    end
  end

  defp action_request(params, idempotency_key) do
    with {:ok, application_key} <- required_text(params, "applicationKey"),
         {:ok, application_version} <- positive_integer(params, "applicationVersion"),
         {:ok, surface_id} <- required_text(params, "surfaceId"),
         {:ok, surface_version} <- positive_integer(params, "surfaceVersion"),
         {:ok, action_id} <- required_text(params, "actionId"),
         {:ok, action_version} <- action_version(params),
         {:ok, action_params} <- action_params(params) do
      {:ok,
       %{
         application_key: application_key,
         application_version: application_version,
         surface_id: surface_id,
         surface_version: surface_version,
         action_id: action_id,
         action_version: action_version,
         params: action_params,
         idempotency_key: idempotency_key
       }}
    end
  end

  defp action_version(params) do
    case {Map.get(params, "actionVersion"), Map.get(params, "version")} do
      {nil, nil} ->
        {:ok, nil}

      {nil, version} ->
        positive_integer_value(version)

      {version, nil} ->
        positive_integer_value(version)

      {action_version, version} when action_version == version ->
        positive_integer_value(version)

      _mismatch ->
        {:error, :invalid_application_request}
    end
  end

  defp query_version(params) do
    case {Map.get(params, "queryVersion"), Map.get(params, "version")} do
      {nil, version} -> positive_integer_value(version)
      {version, nil} -> positive_integer_value(version)
      {query_version, version} when query_version == version -> positive_integer_value(version)
      _mismatch -> {:error, :invalid_application_request}
    end
  end

  defp action_params(params) do
    case {Map.get(params, "params"), Map.get(params, "input")} do
      {nil, input} when is_map(input) -> {:ok, input}
      {action_params, nil} when is_map(action_params) -> {:ok, action_params}
      {action_params, input} when is_map(action_params) and action_params == input -> {:ok, input}
      _invalid -> {:error, :invalid_application_request}
    end
  end

  defp admit_surface(current_scope, route_context, request) do
    with {:ok, admission} <-
           ApplicationHostCatalog.admit_application(
             current_scope,
             route_context,
             request.application_key,
             request.surface_id
           ),
         :ok <- ensure_application_version(admission, request.application_version),
         :ok <- ensure_surface_version(admission.surface, request.surface_version) do
      {:ok, admission}
    end
  end

  defp ensure_application_version(
         %{definition: %ApplicationDefinition{version: version}},
         version
       ),
       do: :ok

  defp ensure_application_version(_admission, _version),
    do: {:error, :application_installation_version_mismatch}

  defp ensure_surface_version(%SurfaceDefinition{version: version}, version), do: :ok

  defp ensure_surface_version(%SurfaceDefinition{}, _version),
    do: {:error, :surface_version_mismatch}

  defp ensure_query_contract(
         %{surface: %SurfaceDefinition{data_contract: contract}},
         %{query_id: query_id, query_version: query_version}
       ) do
    if Map.get(contract, :query_id) == query_id and Map.get(contract, :version) == query_version,
      do: :ok,
      else: {:error, :unsupported_application_query}
  end

  defp declared_action(
         %{
           definition: %ApplicationDefinition{} = definition,
           surface: %SurfaceDefinition{} = surface
         },
         %{action_id: action_id, action_version: action_version}
       ) do
    with true <- action_id in surface.actions,
         {:ok, %ActionDefinition{} = action} <-
           ApplicationDefinition.fetch_action(definition, action_id),
         true <- action.scope == surface.scope,
         :ok <- ensure_declared_action_version(action, action_version),
         :ok <- ActionDefinition.validate(action) do
      {:ok, action}
    else
      false -> {:error, :unsupported_application_action}
      {:error, :undeclared_application_action} -> {:error, :unsupported_application_action}
      _invalid -> {:error, :unsupported_application_action}
    end
  end

  defp ensure_declared_action_version(%ActionDefinition{}, nil), do: :ok

  defp ensure_declared_action_version(%ActionDefinition{version: version}, version),
    do: :ok

  defp ensure_declared_action_version(%ActionDefinition{}, _version),
    do: {:error, :unsupported_application_action}

  defp query_response(admission, %SurfaceDocument{} = document) do
    presentation =
      Declarative.presentation(
        document,
        admission.definition,
        admission.surface,
        DocumentState.form(document),
        nil
      )

    {:ok,
     %{
       "host" => json_safe(host_dto(admission)),
       "navigation" => nil,
       "declarative_surface" => json_safe(presentation),
       "application_surface_rows" => document |> Declarative.table_row_dtos() |> json_safe(),
       "application_surface_activity" =>
         document |> Declarative.activity_item_dtos() |> json_safe(),
       "application_surface_packet_groups" =>
         document |> Declarative.packet_group_dtos() |> json_safe()
     }}
  end

  defp query_response(admission, %{"navigation" => navigation, "data" => data})
       when is_map(navigation) and is_map(data) do
    {:ok,
     %{
       "host" => json_safe(host_dto(admission)),
       "navigation" => json_safe(navigation),
       "trusted_surface" => json_safe(data)
     }}
  end

  defp query_response(_admission, _invalid),
    do: {:error, :invalid_application_surface_document}

  defp host_dto(%{
         definition: %ApplicationDefinition{} = definition,
         installation: installation,
         surface: %SurfaceDefinition{} = surface
       }) do
    %{
      dom_id: host_dom_id(surface.scope),
      application_key: definition.application_key,
      application_version: definition.version,
      application_installation_id: installation.application_installation_id,
      surface_id: surface.surface_id,
      renderer: renderer_name(surface)
    }
  end

  defp renderer_name(%SurfaceDefinition{renderer: {:trusted, _renderer_id}}), do: "trusted"
  defp renderer_name(%SurfaceDefinition{}), do: "declarative"

  defp host_dom_id(:spacecraft), do: "spacecraft-application-host"
  defp host_dom_id(:mission), do: "mission-application-host"

  defp receipt_id(idempotency_key),
    do: "application-host-receipt-" <> idempotency_key

  defp required_text(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" and byte_size(value) <= @max_json_text_bytes ->
        if String.valid?(value), do: {:ok, value}, else: {:error, :invalid_application_request}

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp positive_integer(params, key), do: positive_integer_value(Map.get(params, key))

  defp positive_integer_value(value)
       when is_integer(value) and value > 0 and value <= @max_json_integer,
       do: {:ok, value}

  defp positive_integer_value(_value), do: {:error, :invalid_application_request}

  defp optional_map(params, key) do
    case Map.get(params, key, %{}) do
      value when is_map(value) ->
        if bounded_request_term?(value, 0),
          do: {:ok, value},
          else: {:error, :application_surface_bounds_exceeded}

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp json_safe(value), do: json_safe(value, 0)

  defp json_safe(_value, depth) when depth > @max_json_depth, do: nil
  defp json_safe(nil, _depth), do: nil

  defp json_safe(value, _depth)
       when is_binary(value) and byte_size(value) <= @max_json_text_bytes,
       do: value

  defp json_safe(value, _depth) when is_number(value) do
    if bounded_number?(value), do: value, else: nil
  end

  defp json_safe(value, _depth) when is_boolean(value), do: value
  defp json_safe(%DateTime{} = value, _depth), do: DateTime.to_iso8601(value)
  defp json_safe(%NaiveDateTime{} = value, _depth), do: NaiveDateTime.to_iso8601(value)
  defp json_safe(%_{}, _depth), do: nil

  defp json_safe(value, _depth) when is_atom(value) do
    value = Atom.to_string(value)
    if byte_size(value) <= @max_json_text_bytes, do: value, else: nil
  end

  defp json_safe(value, depth) when is_list(value) do
    reduce_json_list(value, depth, 0, [])
  end

  defp json_safe(value, depth) when is_map(value) do
    if map_size(value) <= @max_json_items do
      Map.new(value, fn {key, item} -> {json_key(key), json_safe(item, depth + 1)} end)
    else
      nil
    end
  end

  defp json_safe(_value, _depth), do: nil

  defp json_key(key) when is_binary(key) and byte_size(key) <= @max_json_text_bytes, do: key

  defp json_key(key) when is_atom(key) do
    value = Atom.to_string(key)
    if byte_size(value) <= @max_json_text_bytes, do: value, else: "invalid"
  end

  defp json_key(key) when is_integer(key) do
    if bounded_number?(key), do: Integer.to_string(key), else: "invalid"
  end

  defp json_key(_key), do: "invalid"

  defp reduce_json_list([], _depth, _count, acc), do: Enum.reverse(acc)

  defp reduce_json_list(_items, _depth, count, _acc) when count >= @max_json_items, do: nil

  defp reduce_json_list([item | rest], depth, count, acc) do
    case json_safe(item, depth + 1) do
      nil when item != nil -> nil
      safe_item -> reduce_json_list(rest, depth, count + 1, [safe_item | acc])
    end
  end

  defp bounded_request_term?(_value, depth) when depth > @max_json_depth, do: false

  defp bounded_request_term?(value, _depth)
       when is_nil(value) or is_boolean(value),
       do: true

  defp bounded_request_term?(value, _depth) when is_number(value), do: bounded_number?(value)

  defp bounded_request_term?(value, _depth) when is_binary(value),
    do: String.valid?(value) and byte_size(value) <= @max_json_text_bytes

  defp bounded_request_term?(value, depth) when is_list(value) do
    reduce_bounded_request_list(value, depth, 0)
  end

  defp bounded_request_term?(value, depth) when is_map(value),
    do: bounded_request_map?(value, depth)

  defp bounded_request_term?(_value, _depth), do: false

  defp bounded_request_map?(value, depth) do
    map_size(value) <= @max_json_items and
      Enum.all?(value, &bounded_request_entry?(&1, depth))
  end

  defp bounded_request_entry?({key, item}, depth) do
    bounded_request_key?(key) and bounded_request_term?(item, depth + 1)
  end

  defp reduce_bounded_request_list([], _depth, _count), do: true

  defp reduce_bounded_request_list(_items, _depth, count) when count >= @max_json_items,
    do: false

  defp reduce_bounded_request_list([item | rest], depth, count) do
    if bounded_request_term?(item, depth + 1),
      do: reduce_bounded_request_list(rest, depth, count + 1),
      else: false
  end

  defp bounded_request_key?(key) when is_binary(key),
    do: String.valid?(key) and byte_size(key) <= @max_json_text_bytes

  defp bounded_request_key?(key) when is_atom(key) do
    byte_size(Atom.to_string(key)) <= @max_json_text_bytes
  end

  defp bounded_request_key?(key) when is_integer(key), do: bounded_number?(key)
  defp bounded_request_key?(_key), do: false

  defp bounded_number?(value) when is_integer(value),
    do: value >= @min_json_integer and value <= @max_json_integer

  defp bounded_number?(value) when is_float(value), do: abs(value) <= @max_json_integer

  defp bounded_number?(_value), do: false
end
