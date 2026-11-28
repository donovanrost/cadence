defmodule CadenceWeb.Console.FleetController do
  @moduledoc "`GET /api/v1/missions/:mission_id/fleet`. Contract: docs/apogee/api/ops.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.{CommandCounts, FleetStatus, MonitoredParameters}
  alias CadenceWeb.Console.FleetJSON

  def show(conn, _params) do
    scope = conn.assigns.current_scope
    mission = conn.assigns.current_mission

    fleet = FleetStatus.load(scope.organization_id, mission.mission_id)
    commands = CommandCounts.load(scope.organization_id, mission.mission_id, scope.user.user_id)

    limits_configured? =
      MonitoredParameters.configured?(scope.organization_id, mission.mission_id)

    json(conn, %{data: FleetJSON.fleet(fleet, commands, limits_configured?)})
  end
end
