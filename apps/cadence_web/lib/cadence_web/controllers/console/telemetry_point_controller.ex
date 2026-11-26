defmodule CadenceWeb.Console.TelemetryPointController do
  @moduledoc """
  M23 point search, `GET /api/v1/missions/:mission_id/telemetry/points`.
  Contract: docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.PointSearch
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, params) do
    with {:ok, limit} <- limit(params["limit"]),
         {:ok, spacecraft_id} <- spacecraft(conn, params["spacecraft_id"]) do
      points =
        PointSearch.search(conn.assigns.current_scope.organization_id, mission_id(conn), %{
          q: params["q"] || "",
          limit: limit,
          spacecraft_id: spacecraft_id
        })

      json(conn, %{data: ConfigJSON.encode(%{points: points})})
    else
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  defp limit(nil), do: {:ok, 50}

  defp limit(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _invalid -> {:error, %{limit: "must be 1 to 200"}}
    end
  end

  defp spacecraft(_conn, nil), do: {:ok, nil}
  defp spacecraft(_conn, ""), do: {:ok, nil}

  defp spacecraft(conn, id) when is_binary(id) do
    case Cadence.SpacecraftStore.fetch_spacecraft(
           conn.assigns.current_scope.organization_id,
           mission_id(conn),
           id
         ) do
      {:ok, _craft} -> {:ok, id}
      _missing -> {:error, %{spacecraft_id: "is not a spacecraft of this mission"}}
    end
  end

  defp spacecraft(_conn, _id), do: {:error, %{spacecraft_id: "must be an id"}}

  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
