defmodule CadenceWeb.Console.ProfileController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/profiles`. Contract: docs/apogee/api/setup.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.ProfileDirectory

  def index(conn, _params) do
    profiles =
      ProfileDirectory.load(
        conn.assigns.current_scope.organization_id,
        conn.assigns.current_mission.mission_id
      )

    json(conn, %{data: %{profiles: profiles}})
  end
end
