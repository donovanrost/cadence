defmodule CadenceWeb.OpsFleetDirectoryPage do
  @moduledoc "Host placement and captured read-only recovery for fleet planning."
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.FleetDirectory
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/planning"
  @id "planning.fleet-directory"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}

    session =
      case socket.assigns[:ops_fleet_directory_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            params: Map.delete(params, "mission_id")
          }
      end

    Component.assign(socket,
      ops_fleet_directory_session: session,
      ops_page: snapshot(scope, session)
    )
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_fleet_directory_session, nil)

  def matches?(socket, %{"path" => path, "id" => @id, "token" => token} = request)
      when map_size(request) == 3 do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_fleet_directory_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def read(socket),
    do: snapshot(socket.assigns.current_scope, socket.assigns.ops_fleet_directory_session)

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    with {:ok, entity} <- Missions.fetch_mission(org, mission),
         {:ok, %{directory: directory}} <- FleetDirectory.load(scope, entity, session.params) do
      Map.merge(envelope, %{status: "ready", data: directory})
    else
      _ -> Map.put(envelope, :status, "unavailable")
    end
  end
end
