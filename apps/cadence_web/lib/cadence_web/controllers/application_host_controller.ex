defmodule CadenceWeb.ApplicationHostController do
  @moduledoc """
  Phoenix boundary for the opt-in Comms application-host vertical slice.

  The browser session is the only source of identity. The route mission and
  request scope are checked against that session before the read-only Comms
  query is evaluated.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias CadenceWeb.CommsOverviewPresenter

  @application_catalog_schema "cadence.first-party-frontend-catalog.v1"
  @application_host_contract "cadence.application-host.v1"
  @problem_schema "cadence.application-host-problem.v1"
  @bridge_path "/api/cadence/application-host/v1"
  @manifest_path "/assets/application-host/comms-overview/mf-manifest.json"
  @host_mission_key :application_host_mission_id

  @spec federated(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def federated(conn, %{"mission_id" => mission_id}) do
    case fetch_mission(conn.assigns.current_scope, mission_id) do
      {:ok, %Mission{} = mission} ->
        render(conn, :federated,
          flash: Phoenix.Controller.get_flash(conn),
          current_scope: conn.assigns.current_scope,
          mission_id: mission.mission_id,
          catalog_url: catalog_url(mission.mission_id)
        )

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Mission not found.")
        |> redirect(to: "/missions")
    end
  end

  @spec catalog(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def catalog(conn, %{"mission_id" => mission_id}) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, %Mission{} = mission} <- fetch_mission(current_scope, mission_id) do
      conn
      |> put_session(@host_mission_key, mission.mission_id)
      |> put_resp_header("cache-control", "no-store")
      |> json(catalog_document(conn, current_scope, mission))
    else
      {:error, _reason} ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())

      _other ->
        problem(conn, :not_found, "mission_not_found", mission_not_found_message())
    end
  end

  @spec query(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def query(conn, %{"mission_id" => mission_id} = params) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, %Mission{} = mission} <- fetch_mission(current_scope, mission_id),
         :ok <- validate_host_mission(conn, mission.mission_id),
         :ok <- validate_request_scope(params, current_scope, mission),
         :ok <- validate_query(params) do
      json(conn, %{
        "queryVersion" => 1,
        "presentation" => CommsOverviewPresenter.build(current_scope, mission)
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
  def actions(conn, %{"mission_id" => mission_id} = params) do
    with %Scope{} = current_scope <- conn.assigns.current_scope,
         {:ok, %Mission{} = mission} <- fetch_mission(current_scope, mission_id),
         :ok <- validate_host_mission(conn, mission.mission_id),
         :ok <- validate_request_scope(params, current_scope, mission) do
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

  defp fetch_mission(
         %Scope{organization_id: organization_id},
         mission_id
       )
       when is_binary(organization_id) and is_binary(mission_id) and mission_id != "" do
    Cadence.Missions.fetch_mission(organization_id, mission_id)
  end

  defp fetch_mission(%Scope{}, _mission_id), do: {:error, :mission_not_found}
  defp fetch_mission(_scope, _mission_id), do: {:error, :mission_not_found}

  defp catalog_document(conn, current_scope, mission) do
    session_id = conn.assigns.application_host_session_id
    csrf_token = get_csrf_token()

    %{
      "schema" => @application_catalog_schema,
      "hostContract" => @application_host_contract,
      "generatedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "session" => %{
        "sessionId" => session_id,
        "csrfToken" => csrf_token,
        "bridgeBaseUrl" => bridge_url(mission.mission_id),
        "context" => context_document(current_scope, mission)
      },
      "applications" => [application_document(conn)]
    }
  end

  defp context_document(
         %Scope{organization_id: organization_id, user: %{display_name: display_name}},
         mission
       ) do
    %{
      "organizationId" => organization_id,
      "missionId" => mission.mission_id,
      "missionName" => mission.display_name,
      "scope" => "mission",
      "spacecraftId" => nil,
      "spacecraftName" => nil,
      "actor" => %{
        "displayName" => display_name,
        "permissions" => ["applications:view"]
      }
    }
  end

  defp application_document(conn) do
    %{
      "applicationKey" => "comms_overview",
      "applicationVersion" => 1,
      "displayName" => "Communications Overview",
      "description" => "Review the saved communications setup for a mission.",
      "package" => %{"packageId" => "cadence.comms_overview", "version" => 1},
      "surface" => %{
        "surfaceId" => "overview",
        "version" => 1,
        "purpose" => "overview",
        "scope" => "mission",
        "placement" => "application_workspace",
        "navigation" => %{"label" => "Overview", "order" => 10},
        "dataContract" => %{"id" => "cadence.comms.overview", "version" => 1},
        "actions" => [],
        "renderer" => %{"kind" => "federated-vue", "exposedModule" => "./Application"}
      },
      "release" => %{
        "federation" => "module_federation",
        "releaseId" => "comms-overview-v1",
        "remoteName" => "cadence_comms_overview",
        "manifestUrl" => url(conn, @manifest_path),
        "exposedModule" => "./Application"
      }
    }
  end

  defp validate_request_scope(
         %{"scope" => scope},
         %Scope{organization_id: organization_id},
         %Mission{mission_id: mission_id}
       )
       when is_binary(organization_id) do
    expected = %{
      "organizationId" => organization_id,
      "missionId" => mission_id,
      "spacecraftId" => nil
    }

    if scope == expected, do: :ok, else: {:invalid_scope, :scope_mismatch}
  end

  defp validate_request_scope(_params, _current_scope, _mission),
    do: {:invalid_scope, :scope_mismatch}

  defp validate_host_mission(conn, mission_id) do
    if get_session(conn, @host_mission_key) == mission_id do
      :ok
    else
      {:invalid_scope, :host_session_mismatch}
    end
  end

  defp validate_query(%{"queryId" => "cadence.comms.overview", "version" => 1}),
    do: :ok

  defp validate_query(_params), do: :unsupported_query

  defp bridge_url(mission_id), do: @bridge_path <> "/missions/" <> URI.encode(mission_id)

  defp catalog_url(mission_id),
    do: ~p"/api/cadence/application-host/v1/missions/#{mission_id}/catalog"

  defp problem(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"schema" => @problem_schema, "code" => code, "message" => message})
  end

  defp invalid_scope_message, do: "The requested application scope is invalid."

  defp mission_not_found_message,
    do: "The requested mission could not be found in the current organization."
end
