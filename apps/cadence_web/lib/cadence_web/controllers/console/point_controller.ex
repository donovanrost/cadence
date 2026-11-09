defmodule CadenceWeb.Console.PointController do
  @moduledoc """
  Per-point reads for Investigate: decimated history (M10) and limit-definition
  intervals (M11). Contract: docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Reads.{PointHistory, PointInfo}
  alias CadenceWeb.Console.{PointJSON, Problem, WindowParams}

  def history(conn, %{"point_id" => point_id} = params) do
    with {:ok, window} <- WindowParams.parse(params, max_points: true),
         {:ok, history} <-
           PointHistory.load(org_id(conn), mission_id(conn), point_id, window) do
      info = PointInfo.fetch(org_id(conn), mission_id(conn), point_id)
      json(conn, %{data: PointJSON.history(point_id, window, history, info)})
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
      {:error, _reason} -> Problem.respond(conn, :history_unavailable)
    end
  end

  def limit_intervals(conn, %{"point_id" => point_id} = params) do
    case WindowParams.parse(params, max_span_s: nil) do
      {:ok, window} ->
        intervals =
          LimitReads.definition_intervals(org_id(conn), mission_id(conn), point_id,
            from_time: window.from,
            to_time: window.to,
            spacecraft_id: window.spacecraft_id
          )

        json(conn, %{data: PointJSON.limit_intervals(point_id, window, intervals)})

      {:error, {:invalid_params, details}} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
