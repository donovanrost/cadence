defmodule CadenceWeb.Console.AppSurfaceController do
  @moduledoc """
  §11 L9 surface host (S1; contract setup.md §App surfaces): everything the console needs to
  load one application surface, a Module Federation component, and let it talk to the server.

  `catalog` is the application-host catalog for that one app and surface, schema unchanged
  (`ApplicationHostCatalog.build/3`; the console checks it with `assertFrontendApplicationCatalog`),
  except `session.context.actor.permissions`, which is the actor's real permissions (closed
  vocabulary below). Like the bridge's own `GET /catalog`, it mints or reuses the host session id
  and pins the host scope, so the bridge's query and actions then work for this surface. The
  session keeps the 16 most recent scopes (L19b); a surface that still gets
  `host_session_mismatch` re-requests this to pin its scope again.

  Permissions: `applications:view` (always), `applications:operate` (the actor passes the policy
  of every action the surface declares, as `ActionDispatcher` enforces it), `activations:request`
  (the surface can request activation and the actor may).
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.{ApplicationInstallations, HostContext, Registry}
  alias Cadence.Auth.Policy
  alias Cadence.Reads.{AppStatus, MissionApps}
  alias Cadence.SpacecraftStore
  alias CadenceWeb.{ApplicationHostCatalog, ApplicationHostSessionState}
  alias CadenceWeb.Console.Problem

  def host(conn, %{"key" => key, "surface_id" => surface_id} = params) do
    scope = conn.assigns.current_scope
    now = DateTime.utc_now()

    with {:ok, definition} <- definition(key),
         :ok <- surface?(definition, surface_id),
         {:ok, route_context} <- route_context(conn, params["spacecraft_id"]),
         {:ok, admitted} <-
           ApplicationHostCatalog.admit_application(scope, route_context, key, surface_id,
             now: now
           ),
         {conn, session_id} = ApplicationHostSessionState.ensure_console_session_id(conn),
         {:ok, catalog} <- catalog(conn, scope, route_context, key, surface_id, session_id, now) do
      host_context = route_context.host_context

      conn
      |> ApplicationHostSessionState.pin_scope(
        ApplicationHostCatalog.scope_document(scope, route_context),
        host_context.mission_id
      )
      |> put_resp_header("cache-control", "no-store")
      |> json(%{
        data: %{
          catalog:
            with_permissions(
              catalog,
              permissions(scope, host_context, definition, admitted.surface)
            ),
          status: AppStatus.status(scope, definition, admitted.installation, host_context),
          surfaces: MissionApps.surfaces(definition)
        }
      })
    else
      {:error, reason} -> error(conn, key, params, reason)
    end
  end

  defp definition(key) do
    case Registry.fetch_available(key) do
      {:ok, definition} -> {:ok, definition}
      {:error, _unknown} -> {:error, :application_not_found}
    end
  end

  defp surface?(definition, surface_id) do
    if Enum.any?(definition.surfaces || [], &(&1.surface_id == surface_id)),
      do: :ok,
      else: {:error, :surface_not_found}
  end

  defp route_context(conn, nil) do
    mission = conn.assigns.current_mission

    {:ok,
     %{host_context: HostContext.mission(mission.mission_id), mission: mission, spacecraft: nil}}
  end

  defp route_context(conn, spacecraft_id) when is_binary(spacecraft_id) and spacecraft_id != "" do
    mission = conn.assigns.current_mission
    scope = conn.assigns.current_scope

    case SpacecraftStore.fetch_spacecraft(
           scope.organization_id,
           mission.mission_id,
           spacecraft_id
         ) do
      {:ok, spacecraft} ->
        {:ok,
         %{
           host_context: HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
           mission: mission,
           spacecraft: spacecraft
         }}

      {:error, _not_found} ->
        {:error, :spacecraft_not_found}
    end
  end

  defp route_context(_conn, _invalid), do: {:error, :spacecraft_not_found}

  # Same options as the bridge's GET /catalog, served from this request's origin.
  defp catalog(conn, scope, route_context, key, surface_id, session_id, now) do
    origin = %URI{scheme: Atom.to_string(conn.scheme), host: conn.host, port: conn.port}

    ApplicationHostCatalog.build(scope, route_context,
      session_id: session_id,
      csrf_token: get_csrf_token(),
      bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
      manifest_url: fn path -> unverified_url(origin, path) end,
      application_key: key,
      surface_id: surface_id,
      now: now
    )
  end

  # todo(authz): under today's Policy, :read_application_catalog and the actions' :operate_mission
  # are the same check, so whoever loads a surface may operate it. Read-only becomes real once
  # Cedar (or a narrower grant) separates them; the vocabulary is ready for it.
  defp permissions(scope, host_context, definition, surface) do
    params = %{organization_id: scope.organization_id, mission_id: host_context.mission_id}

    required =
      for action_id <- surface.actions || [],
          action <- definition.actions || [],
          action.action_id == action_id,
          do: action.required_permission

    {activation, operate} = Enum.split_with(required, &(&1 == "request_activation"))

    ["applications:view"] ++
      if(operate != [] and Enum.all?(operate, &allowed?(scope, &1, params)),
        do: ["applications:operate"],
        else: []
      ) ++
      if(activation != [] and allowed?(scope, "request_activation", params),
        do: ["activations:request"],
        else: []
      )
  end

  # The mapping ActionDispatcher applies to a declared required_permission.
  defp allowed?(scope, "operate_mission", params),
    do: Policy.authorize(scope, :operate_mission, params) == :ok

  defp allowed?(scope, "request_activation", params),
    do: Policy.authorize(scope, :request_activation, params) == :ok

  defp allowed?(_scope, _unknown, _params), do: false

  defp with_permissions(catalog, permissions),
    do: put_in(catalog, ["session", "context", "actor", "permissions"], permissions)

  defp error(conn, key, params, reason)
       when reason in [
              :application_not_installed,
              :application_installation_disabled,
              :application_installation_uninstalled
            ] do
    Problem.respond(conn, :application_not_installed, %{
      status: not_installed_status(conn, key, params)
    })
  end

  defp error(conn, _key, _params, reason)
       when reason in [
              :application_not_found,
              :surface_not_found,
              :spacecraft_not_found,
              :forbidden
            ],
       do: Problem.respond(conn, reason)

  defp error(conn, _key, _params, :unknown_surface), do: Problem.respond(conn, :surface_not_found)

  defp error(conn, _key, _params, _unavailable),
    do: Problem.respond(conn, :application_unavailable)

  defp not_installed_status(conn, key, params) do
    scope = conn.assigns.current_scope

    with {:ok, definition} <- definition(key),
         {:ok, %{host_context: host_context}} <- route_context(conn, params["spacecraft_id"]) do
      installation =
        case ApplicationInstallations.fetch(scope, host_context, key) do
          {:ok, installation} -> installation
          _none -> nil
        end

      AppStatus.status(scope, definition, installation, host_context)
    else
      _unknown -> %{state: :not_installed, label: nil, version: nil}
    end
  end
end
