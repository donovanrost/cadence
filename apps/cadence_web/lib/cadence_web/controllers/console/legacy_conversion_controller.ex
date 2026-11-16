defmodule CadenceWeb.Console.LegacyConversionController do
  @moduledoc """
  TEMPORARY (removed with 9ac6dc8ee): the legacy route conversion (ux U79, director 11-16).
  Older per-spacecraft routing rules become extra routes, one change set per batch of spacecraft,
  each batch alone in its set and reviewed by someone other than its stager.

  - `GET …/routes/legacy-conversion`: progress, the staged batch and what can't be converted
    (`operate_mission`).
  - `POST …/routes/legacy-conversion`: stages the next batch (`manage_mission`); body optional
    `{spacecraft: 1..100}`, default 50.

  Contract: docs/apogee/api/setup.md, "Legacy route conversion".
  """

  use CadenceWeb, :controller

  alias Cadence.Control.LegacyRouteConversion
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def show(conn, _params) do
    case LegacyRouteConversion.progress(scope(conn), mission_id(conn)) do
      {:ok, progress} -> json(conn, %{data: ConfigJSON.encode(progress)})
      {:error, reason} -> ConfigJSON.error(conn, reason)
    end
  end

  def stage(conn, params) do
    with {:ok, spacecraft} <- spacecraft(params),
         {:ok, staged} <-
           LegacyRouteConversion.stage_next_batch(scope(conn), mission_id(conn), spacecraft) do
      conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(staged)})
    else
      {:error, {:invalid_params, :spacecraft}} -> invalid_spacecraft(conn)
      {:error, reason} -> ConfigJSON.error(conn, reason)
    end
  end

  # Absent: domain's default batch. Present: an integer; the range is domain's to judge.
  defp spacecraft(%{"spacecraft" => n}) when is_integer(n), do: {:ok, n}

  defp spacecraft(%{"spacecraft" => _not_an_integer}),
    do: {:error, {:invalid_params, :spacecraft}}

  defp spacecraft(_params), do: {:ok, LegacyRouteConversion.batch_sizes().default}

  defp invalid_spacecraft(conn) do
    %{range: range} = LegacyRouteConversion.batch_sizes()

    Problem.respond(conn, :invalid_params, %{
      "spacecraft" => "Enter a whole number from #{range.first} to #{range.last}."
    })
  end

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
