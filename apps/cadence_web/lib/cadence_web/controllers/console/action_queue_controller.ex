defmodule CadenceWeb.Console.ActionQueueController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/action-queue`. Contract: docs/apogee/api/ops.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.ActionQueue
  alias CadenceWeb.Console.ActionQueueJSON

  def show(conn, _params) do
    scope = conn.assigns.current_scope
    mission = conn.assigns.current_mission

    queue = ActionQueue.load(scope.organization_id, mission.mission_id, scope.user.user_id)

    json(conn, %{data: ActionQueueJSON.queue(queue)})
  end
end
