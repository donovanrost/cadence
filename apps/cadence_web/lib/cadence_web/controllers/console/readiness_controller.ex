defmodule CadenceWeb.Console.ReadinessController do
  @moduledoc "`GET /api/console/v1/missions/:mission_id/readiness`. Contract: docs/apogee/api/setup.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.Readiness
  alias CadenceWeb.Console.Problem

  def show(conn, _params) do
    case Readiness.mission(conn.assigns.current_scope, conn.assigns.current_mission.mission_id) do
      {:ok, readiness} ->
        json(conn, %{
          data: %{
            evaluated_at: readiness.evaluated_at,
            verdict: readiness.verdict,
            areas: readiness.areas,
            findings: Enum.map(readiness.findings, &Map.delete(&1, :area)),
            recent_changes: nil
          }
        })

      {:error, _reason} ->
        Problem.respond(conn, :mission_not_found)
    end
  end
end
