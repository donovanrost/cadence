defmodule CadenceWeb.CatalogCommandSnapshotController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.CatalogJSON, as: CatalogJSON

  alias CadenceWeb.API.CatalogParams, as: CatalogParams

  alias Cadence.Catalog.Command.Compiler, as: CommandCatalogCompiler
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CatalogParams.catalog_command_snapshot_filters(params) do
      snapshots =
        Cadence.Catalog.list_command_snapshots(organization_id, mission_id, filters)
        |> Enum.map(&CatalogJSON.catalog_command_snapshot_summary/1)

      json(conn, %{data: snapshots})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "snapshot_id" => snapshot_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandCatalogSnapshot{} = snapshot} <-
           Cadence.Catalog.fetch_command_snapshot(organization_id, mission_id, snapshot_id) do
      json(conn, %{data: CatalogJSON.catalog_command_snapshot(snapshot)})
    end
  end

  def compile(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "snapshot_id" => snapshot_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandCatalogSnapshot{} = snapshot} <-
           Cadence.Catalog.fetch_command_snapshot(organization_id, mission_id, snapshot_id) do
      compilation = CommandCatalogCompiler.compile(snapshot)

      json(conn, %{
        data: CatalogJSON.catalog_command_compile_result(snapshot, compilation)
      })
    end
  end
end
