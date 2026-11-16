defmodule CadenceWeb.Console.ContactPlanHistoryController do
  @moduledoc """
  U69 A10: `GET /contact-plans/:plan_id/history`, a plan's versions and full decision history.
  Open a version with plan detail's `?version=`. Contract: docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.PlanHistory
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, %{"plan_id" => plan_id}) do
    case PlanHistory.load(
           conn.assigns.current_scope.organization_id,
           conn.assigns.current_mission.mission_id,
           plan_id
         ) do
      {:ok, history} -> json(conn, %{data: ConfigJSON.encode(history)})
      {:error, :plan_not_found} -> Problem.respond(conn, :plan_not_found)
    end
  end
end
