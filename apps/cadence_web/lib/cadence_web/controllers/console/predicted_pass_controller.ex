defmodule CadenceWeb.Console.PredictedPassController do
  @moduledoc """
  Predicted passes (#891, slice 3 of #732). Contract: docs/apogee/api/predicted-passes.md.

    * `GET /missions/:mission_id/predicted-passes`: the passes overlapping `[from, to)`, by
      station or spacecraft optionally, in AOS-then-id order, cursor-paged, with coverage.
    * `GET .../spacecraft/:spacecraft_id/predicted-passes`: the same for one spacecraft.
    * `POST /missions/:mission_id/predicted-passes/recompute`: enqueues a full recompute
      (`:manage_mission`); 202.

  Reads are open to the mission's members. A service identity reaches none of these (they aren't
  listed in `CadenceWeb.Console.ServiceAccess`).
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.Comms.GroundStationStore
  alias Cadence.GroundNetworks.PredictedPasses
  alias Cadence.SpacecraftStore
  alias CadenceWeb.Console.{PredictedPassJSON, Problem}

  def index(conn, params) do
    with {:ok, query} <- query(conn, params, Map.get(params, "spacecraft_id")),
         {:ok, page} <- PredictedPasses.page(org(conn), mission(conn), query) do
      json(conn, PredictedPassJSON.page(page))
    else
      error -> failure(conn, error)
    end
  end

  def spacecraft(conn, %{"spacecraft_id" => spacecraft_id} = params) do
    with {:ok, _spacecraft} <-
           SpacecraftStore.fetch_spacecraft(org(conn), mission(conn), spacecraft_id),
         {:ok, query} <- query(conn, Map.delete(params, "station_id"), nil),
         {:ok, page} <-
           PredictedPasses.page(org(conn), mission(conn), %{query | spacecraft_id: spacecraft_id}) do
      json(conn, PredictedPassJSON.page(page))
    else
      error -> failure(conn, error)
    end
  end

  def recompute(conn, _params) do
    with :ok <-
           Policy.authorize(conn.assigns.current_scope, :manage_mission, %{
             organization_id: org(conn),
             mission_id: mission(conn)
           }),
         {:ok, job} <- PredictedPasses.enqueue_full(org(conn), mission(conn)) do
      conn |> put_status(:accepted) |> json(%{data: %{run_id: job.run_id}})
    else
      error -> failure(conn, error)
    end
  end

  defp query(conn, params, spacecraft_id) do
    with {:ok, from} <- time(params, "from"),
         {:ok, to} <- time(params, "to"),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, station_id} <- station(conn, params["station_id"]),
         {:ok, spacecraft_id} <- known_spacecraft(conn, spacecraft_id) do
      {:ok,
       %{
         from: from,
         to: to,
         limit: limit,
         cursor: params["cursor"],
         station_id: station_id,
         spacecraft_id: spacecraft_id
       }}
    end
  end

  defp time(params, key) do
    with value when is_binary(value) <- params[key],
         {:ok, time, _offset} <- DateTime.from_iso8601(value) do
      {:ok, time}
    else
      _missing -> invalid(key, "must be an ISO 8601 time")
    end
  end

  defp limit(nil), do: {:ok, nil}

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..500 -> {:ok, limit}
      _other -> invalid("limit", "must be 1 to 500")
    end
  end

  defp limit(_value), do: invalid("limit", "must be 1 to 500")

  defp station(_conn, nil), do: {:ok, nil}

  defp station(conn, id) when is_binary(id) do
    case GroundStationStore.fetch_ground_station(org(conn), mission(conn), id) do
      {:ok, _station} -> {:ok, id}
      _missing -> invalid("station_id", "is not a station of this mission")
    end
  end

  defp station(_conn, _id), do: invalid("station_id", "is not a station of this mission")

  defp known_spacecraft(_conn, nil), do: {:ok, nil}

  defp known_spacecraft(conn, id) when is_binary(id) do
    case SpacecraftStore.fetch_spacecraft(org(conn), mission(conn), id) do
      {:ok, _spacecraft} -> {:ok, id}
      _missing -> invalid("spacecraft_id", "is not a spacecraft of this mission")
    end
  end

  defp known_spacecraft(_conn, _id),
    do: invalid("spacecraft_id", "is not a spacecraft of this mission")

  defp invalid(field, reason), do: {:error, {:invalid_param, %{field: field, reason: reason}}}

  defp failure(conn, {:error, {:invalid_param, %{} = details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp failure(conn, {:error, {:invalid_param, field}}),
    do: Problem.respond(conn, :invalid_params, %{field: field, reason: "is not valid"})

  defp failure(conn, {:error, {:window_too_long, max_days}}),
    do: Problem.respond(conn, :predicted_pass_window_too_long, %{max_days: max_days})

  defp failure(conn, {:error, reason}) when is_atom(reason), do: Problem.respond(conn, reason)
  defp failure(conn, {:error, _reason}), do: Problem.respond(conn, :invalid_params)

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
