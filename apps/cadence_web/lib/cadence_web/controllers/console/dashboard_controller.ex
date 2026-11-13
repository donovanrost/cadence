defmodule CadenceWeb.Console.DashboardController do
  @moduledoc """
  Dashboards for the console (owner: api-ops). Contract: docs/apogee/api/dashboards.md.

  D5 `show`: one dashboard's current version resolved for the viewer, through
  `Reads.Dashboards.DashboardPage.load/4` with the runtime admitted by `OpsWorkspaceURL`
  (`from`/`to`, `spacecraft_id`). The snapshot is `WorkspaceSnapshot`'s map, unchanged.
  """

  use CadenceWeb, :controller

  alias Cadence.Dashboards.Documents
  alias Cadence.Reads.Dashboards.DashboardPage
  alias CadenceWeb.Console.{DashboardRuntime, Problem}

  def show(conn, %{"dashboard_id" => dashboard_id} = params) do
    scope = conn.assigns.current_scope
    mission_id = conn.assigns.current_mission.mission_id

    with {:ok, summary} <- summary(scope, mission_id, dashboard_id),
         {:ok, runtime} <- DashboardRuntime.admit(params),
         {:ok, view} <- DashboardPage.load(scope, mission_id, dashboard_id, runtime) do
      json(conn, %{data: body(summary, view)})
    else
      {:error, :not_found} ->
        Problem.respond(conn, :not_found)

      {:error, :invalid_range} ->
        Problem.respond(conn, :invalid_params, %{field: "range"})

      {:error, :invalid_scope} ->
        Problem.respond(conn, :invalid_params, %{field: "spacecraft_id"})

      {:error, _unavailable} ->
        Problem.respond(conn, :dashboard_unavailable)
    end
  end

  # Unknown, archived or another mission's dashboard: 404 (DashboardPage.load can't tell these
  # apart from a failed resolve).
  defp summary(scope, mission_id, dashboard_id) do
    case Documents.fetch_summary(scope.organization_id, mission_id, dashboard_id) do
      {:ok, %{lifecycle_state: "active"} = summary} -> {:ok, summary}
      _missing_or_archived -> {:error, :not_found}
    end
  end

  defp body(summary, view) do
    %{
      dashboard: %{
        id: summary.dashboard_id,
        name: summary.name,
        description: summary.description,
        tags: summary.tags || [],
        current_version: view.saved.version,
        updated_at: view.saved.updated_at
      },
      can_edit: view.author,
      scope_options: view.scope_options,
      snapshot: view.snapshot,
      resolved_at: DateTime.utc_now()
    }
  end
end
