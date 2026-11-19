defmodule CadenceWeb.Console.SpacecraftConfigController do
  @moduledoc """
  `GET /api/console/v1/missions/:mission_id/spacecraft/:spacecraft_id/configuration`
  (Investigate's Configuration tab). Contract: docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.SpacecraftConfig
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"spacecraft_id" => spacecraft_id}) do
    case SpacecraftConfig.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           spacecraft_id
         ) do
      # The revision and change shapes are /config's (ConfigJSON's encoding).
      {:ok, config} -> json(conn, %{data: ConfigJSON.encode(config)})
      {:error, :spacecraft_not_found} -> Problem.respond(conn, :spacecraft_not_found)
    end
  end
end
