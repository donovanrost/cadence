defmodule CadenceWeb.CatalogImporterController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.CatalogJSON, as: CatalogJSON

  alias CadenceWeb.API.CatalogParams, as: CatalogParams

  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CatalogParams.catalog_importer_filters(params) do
      importers =
        Cadence.Catalog.list_importers(filters)
        |> Enum.map(&CatalogJSON.catalog_importer/1)

      json(conn, %{data: importers})
    end
  end
end
