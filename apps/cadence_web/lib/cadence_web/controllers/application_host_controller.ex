defmodule CadenceWeb.ApplicationHostController do
  @moduledoc """
  Phoenix boundary for registry-backed federated application surfaces.

  The browser session is the source of identity. Route resources, durable
  application installations, registered surfaces, and frontend release
  coordinates are resolved before a shell or bridge response is returned.
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias CadenceWeb.{ApplicationHostCatalog, CommsOverviewPresenter}

  @problem_schema "cadence.application-host-problem.v1"
  @host_context_key :application_host_context
  @host_mission_key :application_host_mission_id

  @spec federated(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def federated(
        conn,
        %{"mission_id" => _mission_id, "application_key" => application_key} = params
      ) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         {:ok, application} <-
           ApplicationHostCatalog.admit_application(
             current_scope,
             route_context,
             application_key,
             Map.get(params, "surface_id")
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

  def federated(conn, %{"mission_id" => _mission_id} = params) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params) do
      render_shell(
        conn,
        current_scope,
        route_context,
        "comms_overview",
        "overview",
        "/missions/" <> URI.encode(route_context.mission.mission_id) <> "/comms"
      )
    else
      _reason -> not_found_html(conn)
    end
  end

  @spec catalog(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def catalog(conn, %{"mission_id" => _mission_id} = params) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         {:ok, catalog} <- build_catalog(conn, current_scope, route_context, params) do
      conn
      |> put_session(
        @host_context_key,
        ApplicationHostCatalog.scope_document(current_scope, route_context)
      )
      |> put_session(@host_mission_key, route_context.mission.mission_id)
      |> put_resp_header("cache-control", "no-store")
      |> json(catalog)
    else
      {:error, reason} -> catalog_problem(conn, reason)
      _other -> catalog_problem(conn, :application_catalog_unavailable)
    end
  end

  @spec query(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def query(conn, %{"mission_id" => _mission_id} = params) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         :ok <- validate_host_context(conn, current_scope, route_context),
         :ok <- validate_request_scope(params, current_scope, route_context),
         :ok <- validate_query(params, route_context) do
      json(conn, %{
        "queryVersion" => 1,
        "presentation" => CommsOverviewPresenter.build(current_scope, route_context.mission)
      })
    else
      {:error, _reason} ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())

      {:invalid_scope, _reason} ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :invalid_scope ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :unsupported_query ->
        problem(
          conn,
          :not_found,
          "unsupported_query",
          "The host does not provide that query contract."
        )

      _other ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())
    end
  end

  @spec actions(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def actions(conn, %{"mission_id" => _mission_id} = params) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, route_context} <- fetch_route_context(conn, current_scope, params),
         :ok <- validate_host_context(conn, current_scope, route_context),
         :ok <- validate_request_scope(params, current_scope, route_context) do
      problem(
        conn,
        :not_found,
        "unsupported_action",
        "The host does not provide that action contract."
      )
    else
      {:error, _reason} ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())

      {:invalid_scope, _reason} ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      :invalid_scope ->
        problem(conn, :bad_request, "invalid_scope", invalid_scope_message())

      _other ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())
    end
  end

  defp render_shell(
         conn,
         current_scope,
         route_context,
         application_key,
         surface_id,
         fallback_override \\ nil
       ) do
    render(conn, :federated,
      flash: conn.assigns.flash,
      current_scope: current_scope,
      mission_id: route_context.mission.mission_id,
      spacecraft_id: route_context.host_context.spacecraft_id,
      host_scope: Atom.to_string(route_context.host_context.placement),
      application_key: application_key,
      surface_id: surface_id,
      catalog_url: catalog_url(route_context),
      fallback_href:
        fallback_override ||
          ApplicationHostCatalog.fallback_href(route_context, application_key, surface_id)
    )
  end

  defp build_catalog(conn, current_scope, route_context, params) do
    opts = [
      session_id: conn.assigns.application_host_session_id,
      csrf_token: get_csrf_token(),
      bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
      manifest_url: fn manifest_path -> unverified_url(conn, manifest_path) end
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

  defp fetch_route_context(
         conn,
         %Scope{} = current_scope,
         params
       ) do
    fetch_route_context(current_scope, Map.merge(params, conn.path_params))
  end

  defp fetch_route_context(
         %Scope{} = current_scope,
         %{"mission_id" => mission_id} = params
       ) do
    with {:ok, %Mission{} = mission} <- fetch_mission(current_scope, mission_id) do
      fetch_host_context(current_scope, mission, Map.get(params, "spacecraft_id"))
    end
  end

  defp fetch_route_context(%Scope{}, _params), do: {:error, :mission_not_found}

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

    if get_session(conn, @host_context_key) == expected do
      :ok
    else
      {:invalid_scope, :host_session_mismatch}
    end
  end

  defp validate_query(
         %{"queryId" => "cadence.comms.overview", "version" => 1},
         %{host_context: %HostContext{placement: :mission}}
       ),
       do: :ok

  defp validate_query(_params, _route_context), do: :unsupported_query

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

  defp catalog_problem(conn, reason)
       when reason in [
              :application_not_installed,
              :application_installation_disabled,
              :application_installation_uninstalled,
              :application_installation_scope_required,
              :application_unavailable,
              :invalid_application_request
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
