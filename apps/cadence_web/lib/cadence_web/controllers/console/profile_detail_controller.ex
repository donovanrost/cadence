defmodule CadenceWeb.Console.ProfileDetailController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/profiles/:profile_id`. Contract: docs/apogee/api/setup.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.ProfileDetail
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"profile_id" => profile_id}) do
    case ProfileDetail.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           profile_id
         ) do
      {:ok, detail} -> json(conn, %{data: ConfigJSON.encode(detail)})
      {:error, :spacecraft_type_not_found} -> Problem.respond(conn, :profile_not_found)
    end
  end
end
