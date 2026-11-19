defmodule CadenceWeb.Console.DashboardSettingsController do
  @moduledoc """
  Dashboard slice 5 for the console (owner: api; fe-setup's proposal
  docs/apogee/plans/dashboards-settings.md, contract dashboards.md §D14-D19): activity (D17),
  diagnostics (D18) and export (D19) so far.
  """

  use CadenceWeb, :controller

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, Documents, Management}
  alias Cadence.Reads.Dashboards.{Editor, ExecutionDiagnostics}
  alias CadenceWeb.Console.{ConfigJSON, DashboardActivity, DashboardDiagnostics, Problem}

  # D17 (operator): versions and lifecycle events, one feed, newest first.
  def activity(conn, %{"dashboard_id" => id} = params) do
    case DashboardActivity.load(conn.assigns.current_scope, mission(conn), id, params["before"]) do
      {:ok, page} ->
        json(conn, %{data: ConfigJSON.encode(page)})

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{before: "is not a cursor from this feed"})

      {:error, _unavailable} ->
        Problem.respond(conn, :not_found)
    end
  end

  # D18 (operator): the published version's diagnostics, one row per widget, worst first.
  def diagnostics(conn, %{"dashboard_id" => id}) do
    scope = conn.assigns.current_scope
    mission = mission(conn)

    with {:ok, model} <- ExecutionDiagnostics.load(scope, mission, id),
         {:ok, %Document{} = document} <-
           Documents.fetch_for_mode(scope.organization_id, mission, id, :view) do
      json(conn, %{
        data: ConfigJSON.encode(DashboardDiagnostics.build(model, Editor.outline(document)))
      })
    else
      _unavailable -> Problem.respond(conn, :not_found)
    end
  end

  # D19 (author): the portable bundle as an attachment; the deployment is recorded as before.
  def export(conn, %{"dashboard_id" => id}) do
    scope = conn.assigns.current_scope
    mission = mission(conn)
    user_id = scope.user && scope.user.user_id

    with true <-
           CadenceWeb.DashboardAuthorAuth.authorized?(scope, mission) || {:error, :forbidden},
         {:ok, %Document{} = document} <-
           Dashboards.fetch_document_for_mode(scope.organization_id, mission, id, :edit),
         {:ok, artifact} <- Dashboards.export_bundle(document, exported_by: user_id),
         {:ok, _deployment} <-
           Management.record_deployment(
             scope.organization_id,
             mission,
             document,
             artifact,
             "portable_json",
             created_by: user_id
           ) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{filename(document.name)}.cadence-dashboard.json")
      )
      |> send_resp(200, artifact)
    else
      {:error, :forbidden} -> Problem.respond(conn, :forbidden)
      _missing -> Problem.respond(conn, :not_found)
    end
  end

  # Ported from the legacy DashboardExportController.
  defp filename(name) do
    name
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "dashboard"
      value -> value
    end
  end

  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
