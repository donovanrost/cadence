defmodule CadenceWeb.Console.MissionController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id` — the mission and its organization."

  use CadenceWeb, :controller

  def show(conn, _params) do
    mission = conn.assigns.current_mission
    scope = conn.assigns.current_scope

    json(conn, %{
      data: %{
        id: mission.mission_id,
        slug: mission.slug,
        name: mission.display_name,
        organization: %{
          id: scope.organization.organization_id,
          slug: scope.organization.slug,
          name: scope.organization.display_name
        }
      }
    })
  end
end
