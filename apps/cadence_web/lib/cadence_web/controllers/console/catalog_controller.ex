defmodule CadenceWeb.Console.CatalogController do
  @moduledoc """
  Catalog index (C1), import-run detail and rollout (C3) under
  `/api/v1/missions/:mission_id/catalog`. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Reimport, Upload}

  alias Cadence.Reads.{
    CatalogApids,
    CatalogOverview,
    CatalogRevisionSpacecraft,
    CatalogRollout,
    CatalogSystems
  }

  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, params) do
    database_id = if is_binary(params["database_id"]), do: params["database_id"]
    overview = CatalogOverview.index(org_id(conn), mission_id(conn), database_id)
    json(conn, %{data: ConfigJSON.encode(Map.put(overview, :permissions, permissions(conn)))})
  end

  def import_run(conn, %{"import_run_id" => import_run_id}) do
    case CatalogOverview.import_run(org_id(conn), mission_id(conn), import_run_id) do
      {:ok, run} ->
        json(conn, %{data: ConfigJSON.encode(Map.put(run, :permissions, permissions(conn)))})

      {:error, :import_run_not_found} ->
        Problem.respond(conn, :import_run_not_found)
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

  @doc """
  `GET …/catalog/revisions/:revision_id/systems` (ADR-020 P5): `{revision_id, available, systems}`,
  the SpaceSystems of the revision's model and what each holds.
  """
  def systems(conn, %{"revision_id" => revision_id}) do
    case CatalogSystems.load(org_id(conn), mission_id(conn), revision_id) do
      {:ok, systems} -> json(conn, %{data: systems})
      {:error, :catalog_revision_not_found} -> Problem.respond(conn, :catalog_revision_not_found)
    end
  end

  @doc """
  #678: the spacecraft that use a catalog revision (latest saved configuration, active generation,
  or both), by name then id, `?cursor=` and `?limit=` (1-500, default 200). Contract: setup.md.
  """
  def revision_spacecraft(conn, %{"revision_id" => revision_id} = params) do
    case CatalogRevisionSpacecraft.page(
           org_id(conn),
           mission_id(conn),
           revision_id,
           params["cursor"],
           limit(params["limit"])
         ) do
      {:ok, page} ->
        json(conn, %{
          data: %{spacecraft: page.spacecraft},
          meta: %{total: page.total, next_cursor: page.next_cursor}
        })

      {:error, :catalog_revision_not_found} ->
        Problem.respond(conn, :catalog_revision_not_found)

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})
    end
  end

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp limit(_value), do: nil

  @doc "K1 (L18): one source file, its revisions and import runs."
  def artifact(conn, %{"artifact_id" => artifact_id}) do
    case CatalogOverview.artifact(org_id(conn), mission_id(conn), artifact_id) do
      {:ok, detail} ->
        json(conn, %{data: ConfigJSON.encode(Map.put(detail, :permissions, permissions(conn)))})

      {:error, :artifact_not_found} ->
        Problem.respond(conn, :artifact_not_found)
    end
  end

  @doc "K2 (L18): import the stored file again; refused while a run on it is still going."
  def reimport(conn, %{"artifact_id" => artifact_id}) do
    # The running-import refusal lives in Reimport, so every path gets it (host-action sweep).
    case Reimport.execute(conn.assigns.current_scope, mission_id(conn), artifact_id) do
      {:ok, %{"import_run_id" => run_id}} ->
        conn |> put_status(:accepted) |> json(%{data: %{import_run: %{id: run_id}}})

      {:error, {:import_running, running}} ->
        Problem.respond(conn, :import_running, %{import_run_id: running})

      {:error, :artifact_not_found} ->
        Problem.respond(conn, :artifact_not_found)

      {:error, reason} when reason in [:forbidden, :scope_mismatch] ->
        Problem.respond(conn, :forbidden)

      {:error, _reason} ->
        Problem.respond(conn, :artifact_not_found)
    end
  end

  @doc "K3 (L18): the stored file's bytes, as an attachment."
  def download(conn, %{"artifact_id" => artifact_id}) do
    case Catalog.fetch_artifact(org_id(conn), mission_id(conn), artifact_id) do
      {:ok, artifact} ->
        {bytes, content_type} = Artifact.download_payload(artifact)

        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{artifact.artifact_name}")
        )
        |> send_resp(200, bytes)

      {:error, _not_found} ->
        Problem.respond(conn, :artifact_not_found)
    end
  end

  # Importing is any mission operator: it yields a candidate revision that only an organization
  # admin can approve (`:approve_mission_model`), so the human decision sits at the approval
  # (#1160). `catalog.import` comes from the check the upload and reimport make (`Upload.authorize/2`).
  defp permissions(conn), do: Upload.permissions(conn.assigns.current_scope, mission_id(conn))

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
