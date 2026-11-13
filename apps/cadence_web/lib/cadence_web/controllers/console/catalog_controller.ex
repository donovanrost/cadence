defmodule CadenceWeb.Console.CatalogController do
  @moduledoc """
  Catalog index (C1), import-run detail and rollout (C3) under
  `/api/console/v1/missions/:mission_id/catalog`. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.{CatalogApids, CatalogOverview, CatalogRollout}
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, params) do
    database_id = if is_binary(params["database_id"]), do: params["database_id"]
    overview = CatalogOverview.index(org_id(conn), mission_id(conn), database_id)
    json(conn, %{data: ConfigJSON.encode(overview)})
  end

  def import_run(conn, %{"import_run_id" => import_run_id}) do
    case CatalogOverview.import_run(org_id(conn), mission_id(conn), import_run_id) do
      {:ok, run} -> json(conn, %{data: ConfigJSON.encode(run)})
      {:error, :import_run_not_found} -> Problem.respond(conn, :import_run_not_found)
    end
  end

  # C3 "Roll out to": per profile, what staging this revision would move.
  def rollout(conn, %{"revision_id" => revision_id}) do
    case CatalogRollout.load(org_id(conn), mission_id(conn), revision_id) do
      {:ok, rollout} -> json(conn, %{data: rollout})
      {:error, :catalog_revision_not_found} -> Problem.respond(conn, :catalog_revision_not_found)
    end
  end

  @doc "`GET …/catalog/revisions/:revision_id/apids` (L17): `{revision_id, available, apids}`."
  def apids(conn, %{"revision_id" => revision_id}) do
    case CatalogApids.load(org_id(conn), mission_id(conn), revision_id) do
      {:ok, apids} -> json(conn, %{data: apids})
      {:error, :catalog_revision_not_found} -> Problem.respond(conn, :catalog_revision_not_found)
    end
  end

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
