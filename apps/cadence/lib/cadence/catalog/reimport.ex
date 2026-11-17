defmodule Cadence.Catalog.Reimport do
  @moduledoc """
  Scoped request to import an existing immutable Catalog artifact again. Refused while an import of
  that artifact is still running (`{:import_running, import_run_id}`): every path asks here (the
  console, the mission catalog host action and the native page), so none can start a second.
  The run records who asked (`Catalog.Actor`); before 11-17 it matched the user on `:id` (the key
  is `user_id`), so every reimport stored `%{}`. The run's own model revision counts its runner as
  its importer (`Catalog.ModelImporters`).
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.Catalog.Actor

  def execute(%Scope{} = scope, mission_id, artifact_id)
      when is_binary(mission_id) and is_binary(artifact_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, actor} <- Actor.from_scope(scope),
         {:ok, artifact} <-
           Catalog.fetch_artifact(scope.organization_id, mission_id, artifact_id),
         :ok <- not_running(scope.organization_id, mission_id, artifact.artifact_id),
         {:ok, run} <-
           Catalog.start_import_run(
             scope.organization_id,
             mission_id,
             artifact.artifact_id,
             artifact.format_key,
             requested_by: actor
           ) do
      {:ok,
       %{
         "import_run_id" => run.import_run_id,
         "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
       }}
    end
  end

  def execute(_scope, _mission_id, _artifact_id), do: {:error, :invalid_catalog_request}

  defp not_running(organization_id, mission_id, artifact_id) do
    case organization_id
         |> Catalog.list_import_runs(mission_id, artifact_id: artifact_id)
         |> Enum.find(&(&1.status == :running)) do
      nil -> :ok
      run -> {:error, {:import_running, run.import_run_id}}
    end
  end
end
