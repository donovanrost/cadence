defmodule CadenceWeb.OpsExplorationPage do
  @moduledoc "Host placement for the mission-authorized exploration read."
  alias Cadence.Reads.Dashboards.ExplorationSnapshot
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/explore"
  @id "dashboards.exploration"

  def prepare(socket, info, path, opts \\ [])

  def prepare(socket, %{route: @route, params: params}, _path, opts) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      context: %{organizationId: scope.organization_id, missionId: mission}
    }

    page =
      case ExplorationSnapshot.load(scope, mission, Map.delete(params, "mission_id"), opts) do
        {:ok, model} -> Map.merge(envelope, %{status: "ready", data: model})
        _ -> Map.put(envelope, :status, "unavailable")
      end

    Component.assign(socket, :ops_page, page)
  end

  def prepare(socket, _, _, _), do: socket
end
