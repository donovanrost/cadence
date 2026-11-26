defmodule CadenceWeb.Console.OpsCountsController do
  @moduledoc "`GET /api/v1/missions/:mission_id/counts`. Contract: docs/apogee/api/ops.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.OpsCounts

  def show(conn, _params) do
    counts = OpsCounts.load(conn.assigns.current_scope, conn.assigns.current_mission.mission_id)
    json(conn, %{data: counts})
  end
end
