defmodule CadenceWeb.Console.SpacecraftAppController do
  @moduledoc """
  L19 (owner: api; fe-setup's docs/apogee/plans/spacecraft-apps.md, contract setup.md §A1): the
  apps installable on one spacecraft, with that spacecraft's installations, under
  `…/spacecraft/:spacecraft_id/apps`. Installations are per spacecraft, so the A1 verbs apply here
  too.
  """

  use CadenceWeb, :controller

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Reads.MissionApps
  alias Cadence.SpacecraftStore
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, %{"spacecraft_id" => spacecraft_id}) do
    with {:ok, context} <- context(conn, spacecraft_id),
         {:ok, apps} <- MissionApps.load_at(scope(conn), mission_id(conn), context) do
      json(conn, %{data: ConfigJSON.encode(apps)})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def install(conn, params), do: act(conn, params, &ApplicationInstallations.install/3)
  def disable(conn, params), do: act(conn, params, &ApplicationInstallations.disable/3)
  def uninstall(conn, params), do: act(conn, params, &ApplicationInstallations.uninstall/3)

  defp act(conn, %{"spacecraft_id" => spacecraft_id, "key" => key}, action) do
    with {:ok, context} <- context(conn, spacecraft_id),
         {:ok, _installation} <- action.(scope(conn), context, key),
         {:ok, app} <- MissionApps.app(scope(conn), mission_id(conn), key, context) do
      json(conn, %{data: ConfigJSON.encode(app)})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp context(conn, spacecraft_id) do
    case SpacecraftStore.fetch_spacecraft(
           scope(conn).organization_id,
           mission_id(conn),
           spacecraft_id
         ) do
      {:ok, spacecraft} ->
        {:ok, HostContext.spacecraft(mission_id(conn), spacecraft.spacecraft_id)}

      {:error, _not_found} ->
        {:error, :spacecraft_not_found}
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
