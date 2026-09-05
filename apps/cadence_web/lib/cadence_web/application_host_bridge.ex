defmodule CadenceWeb.ApplicationHostBridge do
  @moduledoc "Canonical JSON bridge for registry-admitted federated application surfaces."

  alias Cadence.Applications.{
    ActionDefinition,
    ActionDispatcher,
    ActionRequest,
    ApplicationDefinition,
    JSONBoundary,
    SurfaceDefinition,
    SurfaceDocument
  }

  alias Cadence.Applications.HostQueryRegistry
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces
  alias CadenceWeb.ApplicationHostCatalog
  alias CadenceWeb.ApplicationSurfaces.{Declarative, DocumentState}

  @type route_context :: ApplicationHostCatalog.route_context()

  @spec query(Scope.t(), route_context(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(current_scope, route_context, params, opts \\ [])

  def query(%Scope{} = current_scope, route_context, params, opts)
      when is_map(params) and is_list(opts) do
    result =
      with :ok <- validate_request(params),
           {:ok, request} <- query_request(params),
           {:ok, admission} <- admit_surface(current_scope, route_context, request, opts),
           :ok <- ensure_query_contract(admission, request) do
        case HostQueryRegistry.dispatch(current_scope, route_context, params) do
          :not_handled -> generic_query(current_scope, route_context, request, admission)
          result -> result
        end
      end

    case result do
      {:error, :unknown_surface} -> {:error, :unsupported_application_query}
      result -> result
    end
  end

  def query(%Scope{}, _route_context, _params, _opts), do: {:error, :invalid_application_request}

  @spec action(Scope.t(), route_context(), map(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def action(current_scope, route_context, params, idempotency_key, opts \\ [])

  def action(
        %Scope{} = current_scope,
        route_context,
        params,
        idempotency_key,
        opts
      )
      when is_map(params) and is_binary(idempotency_key) and
             idempotency_key != "" and is_list(opts) do
    with :ok <- validate_request(params),
         :ok <- validate_idempotency_key(idempotency_key) do
      generic_action(current_scope, route_context, params, idempotency_key, opts)
    end
  end

  def action(%Scope{}, _route_context, _params, _idempotency_key, _opts),
    do: {:error, :invalid_application_request}

  defp generic_query(current_scope, route_context, request, admission) do
    with {:ok, document} <-
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

  defp generic_action(current_scope, route_context, params, idempotency_key, opts) do
    with {:ok, request} <- action_request(params, idempotency_key),
         {:ok, admission} <- admit_surface(current_scope, route_context, request, opts),
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
           ),
         {:ok, action_result} <- action_result(request.application_key, result) do
      safe_output(
        %{
          "receiptId" => receipt_id(idempotency_key),
          "completedAt" => Keyword.fetch!(opts, :now),
          "result" => action_result
        },
        :application_action_output_bounds_exceeded
      )
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
         {:ok, {surface_id, surface_version}} <- optional_surface(params),
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

  defp optional_surface(params) do
    case {Map.get(params, "surfaceId"), Map.get(params, "surfaceVersion")} do
      {nil, nil} ->
        {:ok, {nil, nil}}

      {surface_id, surface_version}
      when is_binary(surface_id) and surface_id != "" and is_integer(surface_version) ->
        with {:ok, surface_id} <- required_text(%{"surfaceId" => surface_id}, "surfaceId"),
             {:ok, surface_version} <- positive_integer_value(surface_version) do
          {:ok, {surface_id, surface_version}}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp admit_surface(current_scope, route_context, request, opts) do
    with {:ok, admission} <-
           ApplicationHostCatalog.admit_application(
             current_scope,
             route_context,
             request.application_key,
             request.surface_id,
             opts
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

  defp ensure_surface_version(%SurfaceDefinition{}, nil), do: :ok

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

    safe_output(
      %{
        "host" => host_dto(admission),
        "navigation" => nil,
        "declarative_surface" => presentation,
        "application_surface_rows" => Declarative.table_row_dtos(document),
        "application_surface_activity" => Declarative.activity_item_dtos(document),
        "application_surface_packet_groups" => Declarative.packet_group_dtos(document)
      },
      :application_host_query_output_bounds_exceeded
    )
  end

  defp query_response(admission, %{"navigation" => navigation, "data" => data})
       when is_map(navigation) and is_map(data) do
    safe_output(
      %{
        "host" => host_dto(admission),
        "navigation" => navigation,
        "trusted_surface" => data
      },
      :application_host_query_output_bounds_exceeded
    )
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
      value when is_binary(value) and value != "" ->
        case JSONBoundary.validate(value) do
          :ok -> {:ok, value}
          {:error, _reason} -> {:error, :invalid_application_request}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp positive_integer(params, key), do: positive_integer_value(Map.get(params, key))

  defp positive_integer_value(value) when is_integer(value) and value > 0 do
    case JSONBoundary.validate(value) do
      :ok -> {:ok, value}
      {:error, _reason} -> {:error, :invalid_application_request}
    end
  end

  defp positive_integer_value(_value), do: {:error, :invalid_application_request}

  defp optional_map(params, key) do
    case Map.get(params, key, %{}) do
      value when is_map(value) ->
        case JSONBoundary.validate(value) do
          :ok -> {:ok, value}
          {:error, _reason} -> {:error, :application_surface_bounds_exceeded}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end

  defp validate_request(params) do
    case JSONBoundary.validate(params) do
      :ok -> :ok
      {:error, _reason} -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp validate_idempotency_key(key) do
    case JSONBoundary.validate(key) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid_application_request}
    end
  end

  defp action_result(application_key, result) do
    result = ActionDispatcher.result(application_key, result)

    if is_nil(result) do
      {:error, :application_action_output_bounds_exceeded}
    else
      safe_output(result, :application_action_output_bounds_exceeded)
    end
  rescue
    _exception -> {:error, :application_action_output_bounds_exceeded}
  catch
    _kind, _value -> {:error, :application_action_output_bounds_exceeded}
  end

  defp safe_output(value, error) do
    case JSONBoundary.safe(value) do
      {:ok, safe} -> {:ok, safe}
      {:error, _reason} -> {:error, error}
    end
  end
end
