defmodule CadenceWeb.Console.AlarmHistoryController do
  @moduledoc """
  Investigate's History tab (ux Investigate.md 7631176e): a spacecraft's alarm episodes over 90
  days, and one episode with its earlier occurrences. Contract: docs/apogee/api/alarms-console.md
  §History.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.AlarmHistory
  alias CadenceWeb.Console.{AlarmHistoryJSON, Problem}

  @scopes %{"alarm" => :alarm, "point" => :point}

  def spacecraft(conn, %{"spacecraft_id" => spacecraft_id} = params) do
    with {:ok, opts} <- opts(params),
         opts = Map.put(opts, :point_id, blank_to_nil(params["point_id"])),
         {:ok, history} <-
           AlarmHistory.spacecraft(scope(conn), mission_id(conn), spacecraft_id, opts) do
      json(conn, %{data: AlarmHistoryJSON.spacecraft(history)})
    else
      error -> problem(conn, error)
    end
  end

  def episode(conn, %{"episode_id" => episode_id} = params) do
    with {:ok, opts} <- opts(params),
         {:ok, history} <- AlarmHistory.episode(scope(conn), mission_id(conn), episode_id, opts) do
      json(conn, %{data: AlarmHistoryJSON.episode(history)})
    else
      error -> problem(conn, error)
    end
  end

  defp problem(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp problem(conn, {:error, reason}) when reason in [:episode_not_found, :forbidden],
    do: Problem.respond(conn, reason)

  defp problem(conn, {:error, :mission_not_found}), do: Problem.respond(conn, :mission_not_found)
  defp problem(conn, _error), do: Problem.respond(conn, :alarms_unavailable)

  # -- params ------------------------------------------------------------------

  defp opts(params) do
    checks = [
      {"limit", limit(params["limit"]), "must be an integer from 1 to 200"},
      {"before", AlarmHistoryJSON.decode_cursor(params["before"]),
       "must be a next_before cursor"},
      {"scope", scope_param(params["scope"]), "must be one of alarm, point"}
    ]

    case for({key, :error, message} <- checks, into: %{}, do: {key, message}) do
      errors when errors == %{} ->
        [{_, {:ok, limit}, _}, {_, {:ok, before}, _}, {_, {:ok, scope}, _}] = checks
        {:ok, %{limit: limit, before: before, scope: scope}}

      errors ->
        {:error, {:invalid_params, errors}}
    end
  end

  defp limit(nil), do: {:ok, 50}

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _other -> :error
    end
  end

  defp limit(_value), do: :error

  defp scope_param(nil), do: {:ok, :alarm}
  defp scope_param(value), do: Map.fetch(@scopes, value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(_value), do: nil

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
