defmodule CadenceWeb.OpsCommandHistoryPage do
  @moduledoc "Host placement for the read-only command request history."
  alias Cadence.Reads.CommandHistory
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/commands/requests/:command_request_id/history"

  def prepare(socket, info, path, opts \\ [])

  def prepare(socket, %{route: @route, params: params}, _path, opts) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    request = params["command_request_id"]

    envelope = %{
      id: "commanding.history",
      slot: "ops.page",
      version: 1,
      context: %{organizationId: scope.organization_id, missionId: mission, resourceId: request}
    }

    page =
      case CommandHistory.load(
             scope,
             mission,
             request,
             Map.drop(params, ["mission_id", "command_request_id"]),
             opts
           ) do
        {:ok, model} -> Map.merge(envelope, %{status: "ready", data: model})
        _ -> Map.put(envelope, :status, "unavailable")
      end

    Component.assign(socket, :ops_page, page)
  end

  def prepare(socket, _, _, _), do: socket
end
