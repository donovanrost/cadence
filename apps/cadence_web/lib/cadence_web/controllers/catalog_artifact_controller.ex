defmodule CadenceWeb.CatalogArtifactController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Catalog.Artifact
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.catalog_artifact_filters(params) do
      artifacts =
        Cadence.Catalog.list_artifacts(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.catalog_artifact/1)

      json(conn, %{data: artifacts})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "catalog_artifact" => artifact_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %Artifact{} = artifact} <-
           ControlPlaneParams.catalog_artifact(
             organization_id,
             mission_id,
             artifact_params,
             uploaded_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, %Artifact{} = persisted_artifact} <-
           Cadence.Catalog.persist_artifact(organization_id, artifact) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.catalog_artifact(persisted_artifact)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "artifact_id" => artifact_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %Artifact{} = artifact} <-
           Cadence.Catalog.fetch_artifact(organization_id, mission_id, artifact_id) do
      json(conn, %{data: ControlPlaneJSON.catalog_artifact(artifact)})
    end
  end
end
