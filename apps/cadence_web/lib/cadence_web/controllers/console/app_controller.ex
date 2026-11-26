defmodule CadenceWeb.Console.AppController do
  @moduledoc """
  A1 apps under `/api/v1/missions/:mission_id/apps`: the list and the
  direct install / disable / uninstall actions. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Reads.MissionApps
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, _params) do
    case MissionApps.load(scope(conn), mission_id(conn)) do
      {:ok, data} -> json(conn, %{data: ConfigJSON.encode(data)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def install(conn, %{"key" => key}), do: act(conn, key, &ApplicationInstallations.install/3)
  def disable(conn, %{"key" => key}), do: act(conn, key, &ApplicationInstallations.disable/3)
  def uninstall(conn, %{"key" => key}), do: act(conn, key, &ApplicationInstallations.uninstall/3)

  defp act(conn, key, action) do
    with {:ok, _installation} <- action.(scope(conn), HostContext.mission(mission_id(conn)), key),
         {:ok, app} <- MissionApps.app(scope(conn), mission_id(conn), key) do
      json(conn, %{data: ConfigJSON.encode(app)})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, reason)
       when reason in [:unknown_application, :application_unavailable, :app_not_found],
       do: Problem.respond(conn, :app_not_found)

  defp error(conn, reason) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, reason) when is_atom(reason), do: Problem.respond(conn, reason)
  defp error(conn, {reason, _detail}) when is_atom(reason), do: Problem.respond(conn, reason)
  defp error(conn, _reason), do: Problem.respond(conn, :app_action_failed)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
