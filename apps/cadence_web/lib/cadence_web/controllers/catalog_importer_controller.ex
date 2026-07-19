defmodule CadenceWeb.CatalogImporterController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.catalog_importer_filters(params) do
      importers =
        Cadence.Catalog.list_importers(filters)
        |> Enum.map(&ControlPlaneJSON.catalog_importer/1)

      json(conn, %{data: importers})
    end
  end
end
