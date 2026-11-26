defmodule CadenceWeb.Console.StationAvailabilityController do
  @moduledoc """
  Ground-station availability (scheduling S7, DECISIONS #39/#44) over
  `Cadence.Comms.StationAvailability` and `Cadence.Reads.StationImpact`.
  Contract: docs/apogee/api/contacts.md. Operators are the session user.
  """

  use CadenceWeb, :controller

  alias Cadence.Comms.StationAvailability
  alias Cadence.Reads.{StationImpact, StationWindowActors}
  alias CadenceWeb.Console.{Problem, StationAvailabilityJSON, WindowParams}

  @kinds ~w(outage maintenance degraded)
  @max_span_s 31 * 86_400

  def index(conn, params) do
    with {:ok, at} <- time(params, "at", DateTime.utc_now()),
         {:ok, statuses} <- StationAvailability.status(scope(conn), mission(conn), :all, at) do
      statuses = named(conn, statuses)

      json(conn, %{
        data: %{at: at, stations: Enum.map(statuses, &StationAvailabilityJSON.status/1)}
      })
    else
      error -> problem(conn, error)
    end
  end

  def show(conn, %{"station_id" => station_id} = params) do
    with {:ok, window} <- window(params),
         {:ok, status} <- StationAvailability.status(scope(conn), mission(conn), station_id),
         {:ok, windows} <-
           StationAvailability.windows(
             scope(conn),
             mission(conn),
             station_id,
             window.from,
             window.to
           ) do
      # One name lookup for the status and its windows (#468).
      [status | windows] = named(conn, [status | windows])

      json(conn, %{
        data: %{
          status: StationAvailabilityJSON.status(status),
          from: window.from,
          to: window.to,
          windows: Enum.map(windows, &StationAvailabilityJSON.window/1)
        }
      })
    else
      error -> problem(conn, error)
    end
  end

  def create_window(conn, %{"station_id" => station_id} = params) do
    with {:ok, attrs} <- window_attrs(params),
         {:ok, window} <-
           StationAvailability.schedule(scope(conn), mission(conn), station_id, attrs) do
      conn
      |> put_status(:created)
      |> json(%{data: StationAvailabilityJSON.window(named(conn, window))})
    else
      error -> problem(conn, error)
    end
  end

  def clear_window(conn, %{"window_id" => window_id} = params) do
    reason = if is_binary(params["reason"]), do: params["reason"]

    case StationAvailability.clear(scope(conn), mission(conn), window_id, reason) do
      {:ok, window} -> json(conn, %{data: StationAvailabilityJSON.window(named(conn, window))})
      error -> problem(conn, error)
    end
  end

  def impact(conn, %{"station_id" => station_id} = params) do
    with {:ok, window} <- window(params),
         {:ok, impact} <-
           StationImpact.impact(scope(conn), mission(conn), station_id, window.from, window.to) do
      json(conn, %{data: impact})
    else
      error -> problem(conn, error)
    end
  end

  # Default window: now to 7 days ahead (the status horizon).
  defp window(params) do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    params
    |> Map.put_new("from", DateTime.to_iso8601(now))
    |> Map.put_new("to", DateTime.to_iso8601(DateTime.add(now, 7 * 86_400)))
    |> WindowParams.parse(max_span_s: @max_span_s)
  end

  defp window_attrs(params) do
    with {:ok, starts_at} <- time(params, "starts_at", nil),
         {:ok, ends_at} <- time(params, "ends_at", nil),
         {:ok, eta} <- time(params, "eta", nil) do
      cond do
        params["kind"] not in @kinds ->
          {:error, {:invalid_params, %{"kind" => "must be one of #{Enum.join(@kinds, ", ")}"}}}

        is_nil(starts_at) ->
          {:error, {:invalid_params, %{"starts_at" => "is required"}}}

        true ->
          {:ok,
           %{
             kind: params["kind"],
             starts_at: starts_at,
             ends_at: ends_at,
             eta: eta,
             reason: if(is_binary(params["reason"]), do: params["reason"]),
             detail: if(is_map(params["detail"]), do: params["detail"], else: %{})
           }}
      end
    end
  end

  defp time(params, key, default) do
    case params[key] do
      nil ->
        {:ok, default}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, at, _offset} -> {:ok, at}
          _error -> {:error, {:invalid_params, %{key => "must be an ISO-8601 timestamp"}}}
        end

      _other ->
        {:error, {:invalid_params, %{key => "must be an ISO-8601 timestamp"}}}
    end
  end

  defp problem(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp problem(conn, {:error, reason})
       when reason in [
              :station_not_found,
              :window_not_found,
              :window_overlaps,
              :window_cleared,
              :invalid_window,
              :forbidden
            ],
       do: Problem.respond(conn, reason)

  defp problem(conn, _error), do: Problem.respond(conn, :not_found)

  # #146 (#468): operators are named only as active members of the mission's organization.
  defp named(conn, views), do: StationWindowActors.named(views, scope(conn).organization_id)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
