defmodule CadenceWeb.Console.TelemetryLatestController do
  @moduledoc """
  `POST /api/console/v1/missions/:mission_id/telemetry/latest {point_ids, spacecraft_ids}` (fe-ops,
  Compose B2): the latest value per spacecraft and point. Contract: docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.TelemetryLatest
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def latest(conn, params) do
    org = conn.assigns.current_scope.organization_id
    mission = conn.assigns.current_mission.mission_id

    case TelemetryLatest.load(org, mission, params["point_ids"], params["spacecraft_ids"]) do
      {:ok, data} -> json(conn, %{data: ConfigJSON.encode(data)})
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end
end
