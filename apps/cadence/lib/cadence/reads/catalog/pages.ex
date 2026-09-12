defmodule Cadence.Reads.Catalog.Pages do
  @moduledoc "Scoped core Catalog presentations, independent of frontend application releases."

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Ids
  alias Cadence.Missions
  alias Cadence.Reads.Catalog.{Artifacts, Databases, Imports, Revisions}

  @subjects %{
    "catalog_index" => [],
    "catalog_database_new" => [],
    "catalog_database_show" => ["catalog_database_id"],
    "catalog_revision_show" => ["catalog_revision_id"],
    "catalog_artifact_show" => ["artifact_id"],
    "catalog_import_run_show" => ["import_run_id"]
  }

  def load(%Scope{} = scope, mission_id, page, params) when is_map(params) do
    with {:ok, keys} <- Map.fetch(@subjects, page),
         true <- Enum.sort(Map.keys(params)) == keys,
         true <- Enum.all?(Map.values(params), &valid_id?/1),
         true <- valid_id?(mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, data} <- dispatch(scope.organization_id, mission_id, page, params) do
      JSONBoundary.safe(data)
    else
      _unavailable -> {:error, :catalog_page_unavailable}
    end
  end

  def load(_scope, _mission_id, _page, _params), do: {:error, :catalog_page_unavailable}

  defp valid_id?(value) when is_binary(value), do: match?({:ok, _}, Ids.path_segment(value))
  defp valid_id?(_value), do: false

  defp dispatch(org, mission, "catalog_index", _), do: Databases.catalog_index(org, mission)

  defp dispatch(_org, mission, "catalog_database_new", _),
    do: {:ok, Databases.catalog_database_new_data(mission)}

  defp dispatch(org, mission, "catalog_database_show", params),
    do: Databases.catalog_database_show(org, mission, params)

  defp dispatch(org, mission, "catalog_revision_show", params),
    do: Revisions.catalog_revision_show(org, mission, params)

  defp dispatch(org, mission, "catalog_artifact_show", params),
    do: Artifacts.catalog_artifact_show(org, mission, params)

  defp dispatch(org, mission, "catalog_import_run_show", params),
    do: Imports.catalog_import_run_show(org, mission, params)
end
