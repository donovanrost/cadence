defmodule CadenceWeb.Console.PointConditionController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id/point-conditions` (#143): the
  current condition of every point of one spacecraft from both stores, critical and caution first,
  stale named. Contract: docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.PointConditions
  alias CadenceWeb.Console.{PointConditionJSON, Problem}

  @states ~w(all attention)

  def index(conn, %{"spacecraft_id" => spacecraft_id} = params) do
    with {:ok, opts} <- options(params),
         {:ok, result} <-
           PointConditions.load(
             conn.assigns.current_scope.organization_id,
             conn.assigns.current_mission.mission_id,
             spacecraft_id,
             opts
           ) do
      json(conn, %{data: PointConditionJSON.points(result), meta: PointConditionJSON.meta(result)})
    else
      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})

      {:error, :spacecraft_not_found} ->
        Problem.respond(conn, :spacecraft_not_found)

      {:error, {:invalid_params, details}} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  defp options(params) do
    state = Map.get(params, "state", "all")

    errors =
      %{}
      |> put_error(state not in @states, :state, "must be one of #{Enum.join(@states, ", ")}")
      |> limit_error(params["limit"])

    if errors == %{} do
      {:ok,
       [
         state: state,
         query: blank_to_nil(params["q"]),
         cursor: blank_to_nil(params["cursor"]),
         limit: limit(params["limit"])
       ]}
    else
      {:error, {:invalid_params, errors}}
    end
  end

  defp limit_error(errors, nil), do: errors
  defp limit_error(errors, ""), do: errors

  defp limit_error(errors, value) do
    case limit(value) do
      nil -> Map.put(errors, :limit, "must be an integer from 1 to 200")
      _ok -> errors
    end
  end

  defp limit(value) when is_binary(value) do
    with {n, ""} <- Integer.parse(value), true <- n in 1..200, do: n, else: (_bad -> nil)
  end

  defp limit(_blank), do: nil

  defp put_error(errors, true, key, message), do: Map.put(errors, key, message)
  defp put_error(errors, false, _key, _message), do: errors

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
