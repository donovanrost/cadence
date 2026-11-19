defmodule CadenceWeb.Console.DataSourceController do
  @moduledoc """
  D1, `GET /api/console/v1/missions/:mission_id/data-sources`. Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.DataSourceDirectory
  alias CadenceWeb.Console.{ConfigJSON, DataSourceWritesController}

  def index(conn, _params) do
    sources =
      DataSourceDirectory.list(
        conn.assigns.current_scope.organization_id,
        conn.assigns.current_mission.mission_id
      )

    permissions =
      DataSourceWritesController.permissions(
        conn.assigns.current_scope,
        conn.assigns.current_mission.mission_id
      )

    json(conn, %{data: ConfigJSON.encode(%{sources: sources, permissions: permissions})})
  end
end
