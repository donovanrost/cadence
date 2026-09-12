defmodule CadenceWeb.OpsWorkspacePage do
  @moduledoc "Host placement of the authorized, published dashboard viewer."
  alias Cadence.Reads.Dashboards.Workspace
  alias CadenceWeb.OpsWorkspaceURL
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/:dashboard_id"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    dashboard = params["dashboard_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, dashboard, path}

    session =
      case socket.assigns[:ops_workspace_session] do
        %{identity: ^identity} = previous -> previous
        _ -> %{identity: identity, token: Ecto.UUID.generate()}
      end

    page = %{
      id: "dashboards.workspace",
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{
        organizationId: scope.organization_id,
        missionId: mission,
        resourceId: dashboard
      }
    }

    page =
      with {:ok, runtime} <- OpsWorkspaceURL.admit(params),
           {:ok, model} <- Workspace.load(scope, mission, dashboard, :view, runtime: runtime) do
        Map.merge(page, %{status: "ready", data: model})
      else
        _ ->
          with {:ok, _} <- OpsWorkspaceURL.admit(params),
               {:ok, requirement} <- Workspace.publication_requirement(scope, mission, dashboard) do
            Map.merge(page, %{status: "ready", data: requirement})
          else
            _ -> Map.put(page, :status, "unavailable")
          end
      end

    Component.assign(socket, ops_workspace_session: session, ops_page: page)
  end

  def prepare(socket, _info, _path), do: Component.assign(socket, :ops_workspace_session, nil)
end
