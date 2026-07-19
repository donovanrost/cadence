defmodule CadenceWeb.CatalogImportRunController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Catalog.ImportRun
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.catalog_import_run_filters(params) do
      import_runs =
        Cadence.Catalog.list_import_runs(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.catalog_import_run/1)

      json(conn, %{data: import_runs})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "catalog_import_run" => run_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, {artifact_id, importer_key, opts}} <-
           ControlPlaneParams.catalog_import_run_request(
             run_params,
             requested_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, %ImportRun{} = import_run} <-
           Cadence.Catalog.start_import_run(
             organization_id,
             mission_id,
             artifact_id,
             importer_key,
             opts
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.catalog_import_run(import_run)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "import_run_id" => import_run_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %ImportRun{} = import_run} <-
           Cadence.Catalog.fetch_import_run(organization_id, mission_id, import_run_id) do
      json(conn, %{data: ControlPlaneJSON.catalog_import_run(import_run)})
    end
  end
end
