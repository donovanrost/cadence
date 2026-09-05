defmodule CadenceWeb.ApplicationHostController do
  @moduledoc """
  Phoenix boundary for registry-backed federated application surfaces.

  The browser session is the source of identity. Route resources, durable
  application installations, registered surfaces, and frontend release
  coordinates are resolved before a shell or bridge response is returned.
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions.Mission
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias CadenceWeb.{ApplicationActionIdempotency, ApplicationHostBridge, ApplicationHostCatalog}

  @problem_schema "cadence.application-host-problem.v1"
  @json_content_type "application/json; charset=utf-8"
  @host_context_key :application_host_context
  @host_mission_key :application_host_mission_id

  @spec federated(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def federated(conn, %{"application_key" => application_key} = params) do
    now = request_boundary_now()

    with %Scope{} = current_scope <- conn.assigns.current_scope,
         :ok <- authorize_route_scope(current_scope, params),
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         {:ok, application} <-
           ApplicationHostCatalog.admit_application(
             current_scope,
             route_context,
             application_key,
             Map.get(params, "surface_id"),
             now: now
           ) do
      render_shell(
        conn,
        current_scope,
        route_context,
        application_key,
        application.surface.surface_id
      )
    else
      _reason -> not_found_html(conn)
    end
  end

  def organization_federated(conn, params),
    do: federated(conn, Map.put(params, "host_scope", "organization"))

  def user_federated(conn, params),
    do: federated(conn, Map.put(params, "host_scope", "user"))

  def admin_federated(conn, params),
    do: federated(conn, Map.put(params, "host_scope", "admin"))

  @spec catalog(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def catalog(conn, params) when is_map(params) do
    now = request_boundary_now()

    with %Scope{} = current_scope <- conn.assigns.current_scope,
         :ok <- authorize_route_scope(current_scope, params),
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         {:ok, catalog} <- build_catalog(conn, current_scope, route_context, params, now) do
      conn
      |> put_host_session(current_scope, route_context)
      |> put_resp_header("cache-control", "no-store")
      |> json(catalog)
    else
      {:error, reason} -> catalog_problem(conn, reason)
      _other -> catalog_problem(conn, :application_catalog_unavailable)
    end
  end

  @spec query(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def query(conn, params) when is_map(params) do
    now = request_boundary_now()

    with %Scope{} = current_scope <- conn.assigns.current_scope,
         :ok <- authorize_route_scope(current_scope, params),
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         :ok <- validate_host_context(conn, current_scope, route_context),
         :ok <- validate_request_scope(params, current_scope, route_context),
         {:ok, response} <-
           ApplicationHostBridge.query(current_scope, route_context, params, now: now) do
      json(conn, response)
    else
      {:error, reason} when reason in [:mission_not_found, :spacecraft_not_found] ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())

      {:error, :no_history} ->
        catalog_problem(conn, :no_history)

      {:error, reason}
      when is_tuple(reason) and elem(reason, 0) in [:database_unavailable, :integrity_failure] ->
        catalog_problem(conn, reason)

      {:error, reason} ->
        bridge_problem(conn, reason)

      {:invalid_scope, _reason} ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :invalid_scope ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :unsupported_application_query ->
        problem(
          conn,
          :not_found,
          "unsupported_query",
          "The host does not provide that query contract."
        )

      :invalid_application_request ->
        problem(
          conn,
          :unprocessable_entity,
          "invalid_input",
          "The application request is invalid."
        )

      reason ->
        bridge_problem(conn, reason)
    end
  end

  @spec actions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def actions(conn, params) when is_map(params) do
    now = request_boundary_now()

    with %Scope{} = current_scope <- conn.assigns.current_scope,
         :ok <- authorize_route_scope(current_scope, params),
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         :ok <- validate_host_context(conn, current_scope, route_context),
         :ok <- validate_request_scope(params, current_scope, route_context),
         {:ok, idempotency_key} <- idempotency_key(conn),
         {:ok, prepared} <-
           ApplicationHostBridge.prepare_action(
             current_scope,
             route_context,
             params,
             idempotency_key,
             now: now
           ),
         {:ok, {_disposition, response}} <-
           ApplicationActionIdempotency.run(
             current_scope,
             prepared.identity,
             idempotency_key,
             prepared.request_document,
             fn ->
               action_execution_outcome(conn, current_scope, route_context, prepared, now)
             end,
             now: now
           ) do
      send_action_response(conn, response)
    else
      {:error, reason} when reason in [:mission_not_found, :spacecraft_not_found] ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())

      {:error, :no_history} ->
        catalog_problem(conn, :no_history)

      {:error, reason}
      when is_tuple(reason) and elem(reason, 0) in [:database_unavailable, :integrity_failure] ->
        catalog_problem(conn, reason)

      {:error, {:idempotency_persistence_failure, _reason}} = reason ->
        bridge_problem(conn, reason)

      {:error, reason} ->
        bridge_problem(conn, reason)

      {:invalid_scope, _reason} ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :invalid_scope ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :invalid_application_request ->
        problem(
          conn,
          :unprocessable_entity,
          "invalid_input",
          "The application request is invalid."
        )

      :unsupported_application_action ->
        problem(
          conn,
          :not_found,
          "unsupported_action",
          "The host does not provide that action contract."
        )

      reason ->
        bridge_problem(conn, reason)
    end
  end

  defp action_execution_outcome(conn, current_scope, route_context, prepared, now) do
    case ApplicationHostBridge.execute_action(current_scope, route_context, prepared, now: now) do
      {:ok, response} -> {:ok, success_action_response(response)}
      {:error, reason} -> {:error, action_problem_response(conn, reason)}
    end
  end

  defp success_action_response(response) do
    %{status: 200, content_type: @json_content_type, body: Jason.encode!(response)}
  end

  defp action_problem_response(conn, reason) do
    conn
    |> action_problem_conn(reason)
    |> stored_response()
  end

  defp action_problem_conn(conn, reason)
       when reason in [:mission_not_found, :spacecraft_not_found],
       do: problem(conn, :not_found, "mission_not_found", mission_not_found_message())

  defp action_problem_conn(conn, :no_history), do: catalog_problem(conn, :no_history)

  defp action_problem_conn(conn, reason)
       when is_tuple(reason) and elem(reason, 0) in [:database_unavailable, :integrity_failure],
       do: catalog_problem(conn, reason)

  defp action_problem_conn(conn, {:invalid_scope, _reason}),
    do: problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

  defp action_problem_conn(conn, :invalid_scope),
    do: problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

  defp action_problem_conn(conn, :invalid_application_request),
    do:
      problem(
        conn,
        :unprocessable_entity,
        "invalid_input",
        "The application request is invalid."
      )

  defp action_problem_conn(conn, :unsupported_application_action),
    do:
      problem(
        conn,
        :not_found,
        "unsupported_action",
        "The host does not provide that action contract."
      )

  defp action_problem_conn(conn, reason), do: bridge_problem(conn, reason)

  defp stored_response(conn) do
    %{
      status: conn.status,
      content_type: List.first(get_resp_header(conn, "content-type")) || @json_content_type,
      body: conn.resp_body
    }
  end

  defp send_action_response(conn, %{status: status, content_type: content_type, body: body}) do
    conn
    |> put_resp_header("content-type", content_type)
    |> send_resp(status, body)
  end

  defp render_shell(
         conn,
         current_scope,
         route_context,
         application_key,
         surface_id,
         fallback_override \\ nil
       ) do
    fallback_result =
      case fallback_override do
        nil -> ApplicationHostCatalog.fallback_href(route_context, application_key, surface_id)
        path when is_binary(path) -> {:ok, path}
        _invalid -> {:error, :invalid_application_request}
      end

    case fallback_result do
      {:ok, fallback_href} ->
        render(conn, :federated,
          flash: conn.assigns.flash,
          current_scope: current_scope,
          organization_id: route_context.host_context.organization_id,
          user_id: route_context.host_context.user_id,
          mission_id: route_context.host_context.mission_id,
          spacecraft_id: route_context.host_context.spacecraft_id,
          host_scope: Atom.to_string(route_context.host_context.placement),
          application_key: application_key,
          surface_id: surface_id,
          catalog_url: catalog_url(route_context),
          fallback_href: fallback_href
        )

      {:error, :invalid_application_request} ->
        not_found_html(conn)
    end
  end

  defp build_catalog(conn, current_scope, route_context, params, now) do
    opts = [
      session_id: conn.assigns.application_host_session_id,
      csrf_token: get_csrf_token(),
      bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
      manifest_url: fn manifest_path -> unverified_url(conn, manifest_path) end,
      now: now
    ]

    opts =
      case Map.get(params, "application_key") do
        application_key when is_binary(application_key) ->
          Keyword.put(opts, :application_key, application_key)

        _missing ->
          opts
      end

    opts =
      case Map.get(params, "surface_id") do
        surface_id when is_binary(surface_id) -> Keyword.put(opts, :surface_id, surface_id)
        _missing -> opts
      end

    ApplicationHostCatalog.build(current_scope, route_context, opts)
  end

  defp request_boundary_now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp fetch_route_context(conn, %Scope{} = current_scope, params) do
    params = Map.merge(params, conn.path_params)

    case Map.get(params, "mission_id") do
      mission_id when is_binary(mission_id) ->
        fetch_route_context(current_scope, params)

      _missing ->
        fetch_generic_route_context(current_scope, params)
    end
  end

  defp fetch_route_context(
         %Scope{} = current_scope,
         %{"mission_id" => mission_id} = params
       ) do
    with {:ok, %Mission{} = mission} <- fetch_mission(current_scope, mission_id) do
      fetch_host_context(current_scope, mission, Map.get(params, "spacecraft_id"))
    end
  end

  defp fetch_route_context(%Scope{} = current_scope, params) do
    fetch_generic_route_context(current_scope, params)
  end

  defp fetch_generic_route_context(%Scope{} = current_scope, params) do
    case requested_scope(params) do
      "organization" ->
        fetch_organization_route_context(current_scope, params)

      "user" ->
        fetch_user_route_context(current_scope, params)

      "admin" ->
        fetch_admin_route_context(current_scope, params)

      _other ->
        {:error, :scope_mismatch}
    end
  end

  defp fetch_organization_route_context(%Scope{organization_id: organization_id}, params)
       when is_binary(organization_id) do
    requested_organization_id = Map.get(params, "organization_id")

    if generic_scope_ids_match?(params, :organization, organization_id) and
         (is_nil(requested_organization_id) or requested_organization_id == organization_id) do
      {:ok,
       %{host_context: HostContext.organization(organization_id), mission: nil, spacecraft: nil}}
    else
      {:error, :scope_mismatch}
    end
  end

  defp fetch_organization_route_context(%Scope{}, _params), do: {:error, :scope_mismatch}

  defp fetch_user_route_context(%Scope{actor_kind: :user, user: %{user_id: user_id}}, params) do
    requested_user_id = Map.get(params, "user_id")

    if generic_scope_ids_match?(params, :user, user_id) and
         (is_nil(requested_user_id) or requested_user_id == user_id) do
      {:ok, %{host_context: HostContext.user(user_id), mission: nil, spacecraft: nil}}
    else
      {:error, :scope_mismatch}
    end
  end

  defp fetch_user_route_context(%Scope{}, _params),
    do: {:error, :authenticated_user_required}

  defp fetch_admin_route_context(%Scope{} = current_scope, params) do
    if Scope.admin_mode?(current_scope) and generic_scope_ids_match?(params, :admin, nil) do
      {:ok, %{host_context: HostContext.admin(), mission: nil, spacecraft: nil}}
    else
      {:error, :forbidden}
    end
  end

  defp authorize_route_scope(
         %Scope{} = current_scope,
         %{"mission_id" => mission_id}
       ) do
    Policy.authorize(current_scope, :read_application_catalog, %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize_route_scope(%Scope{} = current_scope, params) do
    case requested_scope(params) do
      "organization" when is_binary(current_scope.organization_id) ->
        :ok

      "user" when current_scope.actor_kind == :user ->
        :ok

      "admin" ->
        if Scope.admin_mode?(current_scope), do: :ok, else: {:error, :forbidden}

      _other ->
        {:error, :scope_mismatch}
    end
  end

  defp fetch_host_context(%Scope{}, %Mission{} = mission, nil) do
    {:ok,
     %{
       host_context: HostContext.mission(mission.mission_id),
       mission: mission,
       spacecraft: nil
     }}
  end

  defp fetch_host_context(
         %Scope{organization_id: organization_id},
         %Mission{} = mission,
         spacecraft_id
       )
       when is_binary(organization_id) and is_binary(spacecraft_id) and spacecraft_id != "" do
    with {:ok, %Spacecraft{} = spacecraft} <-
           SpacecraftStore.fetch_spacecraft(organization_id, mission.mission_id, spacecraft_id) do
      {:ok,
       %{
         host_context: HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
         mission: mission,
         spacecraft: spacecraft
       }}
    end
  end

  defp fetch_host_context(_current_scope, _mission, _spacecraft_id),
    do: {:error, :spacecraft_not_found}

  defp fetch_mission(%Scope{organization_id: organization_id}, mission_id)
       when is_binary(organization_id) and is_binary(mission_id) and mission_id != "" do
    Cadence.Missions.fetch_mission(organization_id, mission_id)
  end

  defp fetch_mission(%Scope{}, _mission_id), do: {:error, :mission_not_found}

  defp validate_request_scope(
         %{"scope" => scope},
         %Scope{} = current_scope,
         route_context
       ) do
    expected = ApplicationHostCatalog.scope_document(current_scope, route_context)

    if scope == expected, do: :ok, else: {:invalid_scope, :scope_mismatch}
  end

  defp validate_request_scope(_params, _current_scope, _route_context),
    do: {:invalid_scope, :scope_mismatch}

  defp validate_host_context(conn, current_scope, route_context) do
    expected = ApplicationHostCatalog.scope_document(current_scope, route_context)
    expected_mission_id = route_context.host_context.mission_id

    if get_session(conn, @host_context_key) == expected and
         get_session(conn, @host_mission_key) == expected_mission_id do
      :ok
    else
      {:invalid_scope, :host_session_mismatch}
    end
  end

  defp put_host_session(conn, current_scope, route_context) do
    conn =
      put_session(
        conn,
        @host_context_key,
        ApplicationHostCatalog.scope_document(current_scope, route_context)
      )

    case route_context.host_context.mission_id do
      mission_id when is_binary(mission_id) -> put_session(conn, @host_mission_key, mission_id)
      _generic -> delete_session(conn, @host_mission_key)
    end
  end

  defp requested_scope(%{"host_scope" => scope}) when is_binary(scope), do: scope
  defp requested_scope(%{"scope" => scope}) when is_binary(scope), do: scope

  defp requested_scope(%{"scope" => %{"scope" => scope}}) when is_binary(scope),
    do: scope

  defp requested_scope(_params), do: nil

  defp generic_scope_ids_match?(params, scope, expected_id) do
    keys = ["organization_id", "user_id", "mission_id", "spacecraft_id"]

    allowed_key =
      if scope == :organization, do: "organization_id", else: if(scope == :user, do: "user_id")

    Enum.all?(keys, fn key ->
      value = Map.get(params, key)

      (key == allowed_key and value in [nil, expected_id]) or
        (key != allowed_key and is_nil(value))
    end)
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key] when is_binary(key) and key != "" -> {:ok, key}
      _other -> {:error, :idempotency_key_required}
    end
  end

  defp bridge_problem(conn, :idempotency_key_required) do
    problem(
      conn,
      :bad_request,
      "idempotency_key_required",
      "The Idempotency-Key header is required."
    )
  end

  defp bridge_problem(conn, :malformed_idempotency_key) do
    problem(
      conn,
      :bad_request,
      "invalid_idempotency_key",
      "The Idempotency-Key header is invalid or exceeds the permitted size."
    )
  end

  defp bridge_problem(conn, :idempotency_key_collision) do
    problem(
      conn,
      :conflict,
      "idempotency_key_collision",
      "The Idempotency-Key was already used for a different request."
    )
  end

  defp bridge_problem(conn, :idempotency_in_progress) do
    conn
    |> put_resp_header("retry-after", "1")
    |> problem(
      :too_early,
      "action_in_progress",
      "An identical action is already in progress. Retry after it completes."
    )
  end

  defp bridge_problem(conn, reason)
       when reason in [:active_generation_unavailable, :idempotency_secret_unavailable] do
    problem(
      conn,
      :service_unavailable,
      "idempotency_unavailable",
      "The action cannot be safely executed until durable idempotency is available."
    )
  end

  defp bridge_problem(conn, {:idempotency_persistence_failure, _reason}) do
    problem(
      conn,
      :service_unavailable,
      "idempotency_unavailable",
      "The action cannot be safely executed until durable idempotency is available."
    )
  end

  defp bridge_problem(conn, reason) when reason in [:claim_lost, :action_indeterminate] do
    problem(
      conn,
      :conflict,
      "action_indeterminate",
      "The action may have executed, but its durable result is unavailable. Operator action is required."
    )
  end

  defp bridge_problem(conn, reason)
       when reason in [
              :application_installation_version_mismatch,
              :application_installation_scope_required,
              :application_not_installed,
              :application_installation_disabled,
              :application_installation_uninstalled,
              :application_unavailable,
              :unsupported_application_host_context
            ] do
    problem(
      conn,
      :not_found,
      "application_unavailable",
      "The requested application is not available in this scope."
    )
  end

  defp bridge_problem(conn, reason)
       when reason in [
              :unknown_application_release,
              :surface_version_mismatch,
              :surface_not_found,
              :undeclared_application_surface
            ] do
    problem(
      conn,
      :not_found,
      "surface_not_found",
      "The requested application surface is not declared."
    )
  end

  defp bridge_problem(conn, reason)
       when reason in [
              :unsupported_application_surface_query,
              :invalid_application_surface_query_contract,
              :unknown_application_surface_query,
              :unsupported_application_query,
              :application_query_identity_mismatch,
              :invalid_application_host_query_provider_registry,
              :invalid_application_host_query,
              :invalid_application_host_query_output,
              :application_host_query_output_bounds_exceeded
            ] do
    problem(
      conn,
      :not_found,
      "unsupported_query",
      "The host does not provide that query contract."
    )
  end

  defp bridge_problem(conn, reason)
       when reason in [
              :undeclared_application_action,
              :unsupported_application_action,
              :unsupported_application_action_scope,
              :unknown_application_action_provider
            ] do
    problem(
      conn,
      :not_found,
      "unsupported_action",
      "The host does not provide that action contract."
    )
  end

  defp bridge_problem(conn, :forbidden) do
    problem(
      conn,
      :forbidden,
      "forbidden",
      "You do not have authority to access this application contract."
    )
  end

  defp bridge_problem(conn, {:packet_binding_configuration_version_conflict, _expected, _current}) do
    problem(
      conn,
      :conflict,
      "packet_binding_version_conflict",
      "Packet bindings changed. Reload the surface and try again."
    )
  end

  defp bridge_problem(conn, {:application_configuration_version_conflict, _expected, _current}) do
    problem(
      conn,
      :conflict,
      "configuration_version_conflict",
      "The application configuration changed. Reload the surface and try again."
    )
  end

  defp bridge_problem(conn, %Ecto.Changeset{}) do
    problem(conn, :unprocessable_entity, "invalid_input", "The application request is invalid.")
  end

  defp bridge_problem(conn, _reason) do
    problem(conn, :unprocessable_entity, "invalid_input", "The application request is invalid.")
  end

  defp catalog_url(
         %{host_context: %HostContext{placement: placement} = host_context} = route_context
       )
       when placement in [:organization, :user, :admin] do
    base = ApplicationHostCatalog.bridge_base_path(route_context) <> "/catalog"

    query =
      case placement do
        :organization ->
          %{"scope" => "organization", "organization_id" => host_context.organization_id}

        :user ->
          %{"scope" => "user", "user_id" => host_context.user_id}

        :admin ->
          %{"scope" => "admin"}
      end

    base <> "?" <> URI.encode_query(query)
  end

  defp catalog_url(route_context),
    do: ApplicationHostCatalog.bridge_base_path(route_context) <> "/catalog"

  defp catalog_problem(conn, :unknown_application_release) do
    problem(
      conn,
      :not_found,
      "application_release_unavailable",
      "The requested application release is not available."
    )
  end

  defp catalog_problem(conn, :unknown_surface) do
    problem(
      conn,
      :not_found,
      "surface_not_found",
      "The requested application surface is not declared."
    )
  end

  defp catalog_problem(conn, :forbidden) do
    problem(
      conn,
      :forbidden,
      "forbidden",
      "You do not have authority to access this application catalog."
    )
  end

  defp catalog_problem(conn, :no_history) do
    problem(
      conn,
      :not_found,
      "application_unavailable",
      "The requested application is not available in this scope."
    )
  end

  defp catalog_problem(conn, reason)
       when is_tuple(reason) and elem(reason, 0) in [:database_unavailable, :integrity_failure] do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> problem(
      :service_unavailable,
      "application_catalog_unavailable",
      "The application catalog is temporarily unavailable."
    )
  end

  defp catalog_problem(conn, reason)
       when reason in [
              :application_catalog_bounds_exceeded,
              :application_installation_bounds_exceeded,
              :application_not_installed,
              :application_installation_disabled,
              :application_installation_uninstalled,
              :application_installation_scope_required,
              :application_unavailable,
              :invalid_application_request,
              :scope_mismatch,
              :authenticated_user_required
            ] do
    problem(
      conn,
      :not_found,
      "application_unavailable",
      "The requested application is not available in this scope."
    )
  end

  defp catalog_problem(conn, _reason),
    do: problem(conn, :not_found, "mission_not_found", mission_not_found_message())

  defp not_found_html(conn) do
    conn
    |> put_flash(:error, "Application not found.")
    |> redirect(to: "/missions")
  end

  defp problem(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"schema" => @problem_schema, "code" => code, "message" => message})
  end

  defp invalid_scope_message, do: "The requested application scope is invalid."

  defp mission_not_found_message,
    do: "The requested mission could not be found in the current organization."
end
