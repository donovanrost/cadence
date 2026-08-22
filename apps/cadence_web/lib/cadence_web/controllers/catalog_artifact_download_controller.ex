defmodule CadenceWeb.CatalogArtifactDownloadController do
  @moduledoc false

  use CadenceWeb, :controller

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Missions

  def show(conn, %{"mission_id" => mission_id, "artifact_id" => artifact_id}) do
    scope = conn.assigns.current_scope

    with {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, artifact} <-
           Catalog.fetch_artifact(scope.organization_id, mission_id, artifact_id) do
      {bytes, content_type} = Artifact.download_payload(artifact)

      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{artifact.artifact_name}")
      )
      |> send_resp(200, bytes)
    else
      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> text("Not found")
    end
  end
end
