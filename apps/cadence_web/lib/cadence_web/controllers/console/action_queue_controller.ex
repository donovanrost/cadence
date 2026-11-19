defmodule CadenceWeb.Console.ActionQueueController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/action-queue`. Contract: docs/apogee/api/ops.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.ActionQueue
  alias CadenceWeb.Console.ActionQueueJSON

  def show(conn, _params) do
    queue = ActionQueue.load(conn.assigns.current_scope, conn.assigns.current_mission.mission_id)

    json(conn, %{data: ActionQueueJSON.queue(queue)})
  end
end
