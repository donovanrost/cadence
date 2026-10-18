defmodule CadenceWeb.OpsSharedViewPage do
  @moduledoc "Read-only host placement for domain-owned share and snapshot viewers."
  alias Cadence.Reads.Dashboards.SharedViews
  alias Phoenix.Component

  @routes %{
    "/missions/:mission_id/ops/dashboard-shares/:share_id" =>
      {:share, "share_id", "dashboards.share"},
    "/missions/:mission_id/ops/dashboard-snapshots/:snapshot_id" =>
      {:snapshot, "snapshot_id", "dashboards.snapshot"}
  }
  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@routes, route) do
    {kind, key, contribution} = @routes[route]
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    id = params[key]
    identity = {scope.organization_id, scope.user.user_id, mission, id, kind, path}

    session =
      case socket.assigns[:ops_shared_view_session] do
        %{identity: ^identity} = previous -> previous
        _ -> %{identity: identity, token: Ecto.UUID.generate()}
      end

    page = %{
      id: contribution,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: scope.organization_id, missionId: mission, resourceId: id}
    }

    page =
      case SharedViews.load(scope, mission, kind, id) do
        {:ok, model} -> Map.merge(page, %{status: "ready", data: model})
        _ -> Map.put(page, :status, "unavailable")
      end

    Component.assign(socket, ops_shared_view_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_shared_view_session, nil)
end
