defmodule CadenceWeb.Console.SpacecraftController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/spacecraft`. Contract: docs/apogee/api/setup.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.SpacecraftDirectory

  def index(conn, _params) do
    rows =
      SpacecraftDirectory.load(
        conn.assigns.current_scope.organization_id,
        conn.assigns.current_mission.mission_id
      )

    json(conn, %{data: %{spacecraft: rows}})
  end
end
