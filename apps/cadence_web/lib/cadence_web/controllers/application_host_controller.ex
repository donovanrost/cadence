defmodule CadenceWeb.ApplicationHostController do
  @moduledoc """
  Phoenix boundary for the mission and spacecraft application bridge (`query` and `actions`).

  The browser session is the source of identity. Route resources, durable
  application installations and registered surfaces are resolved before a
  bridge response is returned. The console mints the host session through its
  app-surface controller.
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.ActionFailure
  alias Cadence.Applications.HostContext
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions.Mission
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias CadenceWeb.{ApplicationActionIdempotency, ApplicationHostBridge, ApplicationHostCatalog}

  @problem_schema "cadence.application-host-problem.v1"
  @json_content_type "application/json; charset=utf-8"

  @spec query(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def query(conn, params) when is_map(params) do
    now = request_boundary_now()

    with %Scope{} = current_scope <- conn.assigns.current_scope,
         :ok <- authorize_route_scope(current_scope, conn.path_params),
         {:ok, route_context} <- fetch_route_context(current_scope, conn.path_params),
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
         :ok <- authorize_route_scope(current_scope, conn.path_params),
         {:ok, route_context} <- fetch_route_context(current_scope, conn.path_params),
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

  # Inside the idempotency closure a failed action's problem is DATA: the ledger stores it and
  # send_action_response sends it, once. Sending it here as well wrote a second response on the
  # same keep-alive connection, which the browser read as its next request's answer (#230).
  defp action_problem_response(conn, reason) do
    conn
    |> put_private(:application_host_problem_as_data, true)
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

  # Stores status, content type and body only: a header a problem sets inside the action
  # closure (e.g. retry-after) would be dropped from the stored and replayed response (api-ops).
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

  defp request_boundary_now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp fetch_route_context(%Scope{} = current_scope, %{"mission_id" => mission_id} = params) do
    with {:ok, %Mission{} = mission} <- fetch_mission(current_scope, mission_id) do
      fetch_host_context(current_scope, mission, Map.get(params, "spacecraft_id"))
    end
  end

  defp authorize_route_scope(%Scope{} = current_scope, %{"mission_id" => mission_id}) do
    Policy.authorize(current_scope, :read_application_catalog, %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    })
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

    if CadenceWeb.ApplicationHostSessionState.pinned?(conn, expected, expected_mission_id) do
      :ok
    else
      {:invalid_scope, :host_session_mismatch}
    end
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

  defp bridge_problem(conn, %ActionFailure{code: code, message: message}) do
    problem(conn, :unprocessable_entity, code, message)
  end

  defp bridge_problem(conn, %Ecto.Changeset{}) do
    problem(conn, :unprocessable_entity, "invalid_input", "The application request is invalid.")
  end

  defp bridge_problem(conn, _reason) do
    problem(conn, :unprocessable_entity, "invalid_input", "The application request is invalid.")
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

  defp problem(
         %Plug.Conn{private: %{application_host_problem_as_data: true}} = conn,
         status,
         code,
         message
       ) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(status, Jason.encode!(problem_body(code, message)))
  end

  defp problem(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(problem_body(code, message))
  end

  defp problem_body(code, message),
    do: %{"schema" => @problem_schema, "code" => code, "message" => message}

  defp invalid_scope_message, do: "The requested application scope is invalid."

  defp mission_not_found_message,
    do: "The requested mission could not be found in the current organization."
end
