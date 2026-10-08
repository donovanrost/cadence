defmodule CadenceWeb.ContactWorkspaceController do
  @moduledoc "Resource-scoped HTTP boundary for the client-routed contact workspace."
  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.Contacts.ScheduleOperations
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.{ContactRecord, ContactSchedule}
  alias CadenceWeb.HostContext

  def show(conn, _params) do
    case authorize(conn) do
      {:ok, scope, mission} ->
        context =
          conn.assigns
          |> Map.merge(%{
            current_mission: mission,
            nav_context: :mission,
            ops_nav_item: :contacts
          })
          |> HostContext.from_assigns()

        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_layout(false)
        |> render(:show,
          bootstrap: %{
            version: 1,
            actor_id: scope.user.user_id,
            organization_id: scope.organization_id,
            mission_id: mission.mission_id,
            context: context
          }
        )

      _ ->
        conn |> put_status(:not_found) |> text("Mission unavailable")
    end
  end

  def schedule(conn, _params) do
    resource(conn, fn scope, mission ->
      with {:ok, _query} <- ContactSchedule.admit_query(conn.query_params),
           do: ContactSchedule.load(scope, mission, conn.query_params)
    end)
  end

  def record(conn, _params) do
    resource(conn, fn scope, mission ->
      # A query parameter can never replace the resource captured by the router.
      params = Map.put(conn.query_params, "contact_id", conn.path_params["contact_id"])
      ContactRecord.load(scope, mission, params)
    end)
  end

  def execute(conn, _params) do
    resource(conn, fn scope, mission ->
      ScheduleOperations.request(
        scope,
        mission.mission_id,
        conn.path_params["action"],
        conn.body_params
      )
    end)
  end

  defp resource(conn, operation) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with :ok <- same_session(conn, conn.assigns.current_scope),
         {:ok, scope, mission} <- authorize(conn),
         {:ok, data} <- operation.(scope, mission) do
      json(conn, %{
        version: 1,
        actor_id: scope.user.user_id,
        organization_id: scope.organization_id,
        mission_id: mission.mission_id,
        data: data
      })
    else
      {:error, :session_changed} ->
        problem(conn, :conflict, "session_changed")

      {:error, :unavailable} ->
        problem(conn, :not_found, "unavailable")

      {:error, reason} when reason in [:contact_record_not_found, :spacecraft_not_found] ->
        problem(conn, :not_found, "unavailable")

      _ ->
        problem(conn, :unprocessable_entity, "invalid_request")
    end
  end

  defp authorize(conn) do
    scope = conn.assigns.current_scope
    mission_id = conn.path_params["mission_id"]

    with %{user: %{lifecycle_state: :active}, organization_id: org} when is_binary(org) <- scope,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: org,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(org, mission_id) do
      {:ok, scope, mission}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp same_session(conn, scope) do
    if get_req_header(conn, "x-cadence-workspace-user") == [scope.user.user_id] and
         get_req_header(conn, "x-cadence-workspace-organization") == [scope.organization_id],
       do: :ok,
       else: {:error, :session_changed}
  end

  defp problem(conn, status, code), do: conn |> put_status(status) |> json(%{code: code})
end
