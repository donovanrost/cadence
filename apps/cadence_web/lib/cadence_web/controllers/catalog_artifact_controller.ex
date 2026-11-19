defmodule CadenceWeb.CatalogArtifactController do
  use CadenceWeb, :controller

  action_fallback(CadenceWeb.FallbackController)

  alias CadenceWeb.API.CatalogJSON, as: CatalogJSON

  alias CadenceWeb.API.CatalogParams, as: CatalogParams

  alias Cadence.Catalog.Artifact
  alias Cadence.Reads.Catalog.Requesters
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CatalogParams.catalog_artifact_filters(params) do
      artifacts = Cadence.Catalog.list_artifacts(organization_id, mission_id, filters)
      names = Requesters.names(organization_id, Enum.map(artifacts, & &1.uploaded_by))

      json(conn, %{data: Enum.map(artifacts, &CatalogJSON.catalog_artifact(&1, names))})
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
           CatalogParams.catalog_artifact(
             organization_id,
             mission_id,
             artifact_params,
             uploaded_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, %Artifact{} = persisted_artifact} <-
           Cadence.Catalog.persist_artifact(organization_id, artifact) do
      conn
      |> put_status(:created)
      |> json(%{data: one(organization_id, persisted_artifact)})
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
      json(conn, %{data: one(organization_id, artifact)})
    end
  end

  # #366: uploaded_by in #146's shape, named under the artifact's organization only.
  defp one(organization_id, artifact),
    do:
      CatalogJSON.catalog_artifact(
        artifact,
        Requesters.names(organization_id, [artifact.uploaded_by])
      )
end
