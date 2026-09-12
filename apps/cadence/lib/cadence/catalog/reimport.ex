defmodule Cadence.Catalog.Reimport do
  @moduledoc "Scoped request to import an existing immutable Catalog artifact."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog

  def execute(%Scope{} = scope, mission_id, artifact_id)
      when is_binary(mission_id) and is_binary(artifact_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, artifact} <-
           Catalog.fetch_artifact(scope.organization_id, mission_id, artifact_id),
         {:ok, run} <-
           Catalog.start_import_run(
             scope.organization_id,
             mission_id,
             artifact.artifact_id,
             artifact.format_key,
             requested_by: actor(scope)
           ) do
      {:ok,
       %{
         "import_run_id" => run.import_run_id,
         "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
       }}
    end
  end

  def execute(_scope, _mission_id, _artifact_id), do: {:error, :invalid_catalog_request}

  defp actor(%Scope{user: %{id: id, email: email}}), do: %{user_id: id, email: email}
  defp actor(%Scope{}), do: %{}
end
