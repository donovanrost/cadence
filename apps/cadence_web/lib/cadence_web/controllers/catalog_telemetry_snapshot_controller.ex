defmodule CadenceWeb.CatalogTelemetrySnapshotController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.catalog_telemetry_snapshot_filters(params) do
      snapshots =
        Cadence.list_catalog_telemetry_snapshots(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.catalog_telemetry_snapshot_summary/1)

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
         {:ok, %TelemetryCatalogSnapshot{} = snapshot} <-
           Cadence.fetch_catalog_telemetry_snapshot(organization_id, mission_id, snapshot_id) do
      json(conn, %{data: ControlPlaneJSON.catalog_telemetry_snapshot(snapshot)})
    end
  end

  def recompile(conn, %{
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
         {:ok, compilation} <-
           Cadence.recompile_catalog_telemetry_snapshot(organization_id, mission_id, snapshot_id) do
      json(conn, %{data: ControlPlaneJSON.catalog_telemetry_recompile_result(compilation)})
    end
  end

  def runtime_diff(conn, %{
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
         {:ok, diff_report} <-
           Cadence.diff_catalog_telemetry_snapshot_runtime(
             organization_id,
             mission_id,
             snapshot_id
           ) do
      json(conn, %{data: ControlPlaneJSON.catalog_telemetry_runtime_diff(diff_report)})
    end
  end

  def materialize_runtime(conn, %{
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
         {:ok, materialization} <-
           Cadence.materialize_catalog_telemetry_snapshot_runtime(
             organization_id,
             mission_id,
             snapshot_id
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.catalog_telemetry_materialization_result(materialization)})
    end
  end
end
