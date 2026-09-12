defmodule Cadence.Reads.ApplicationSurfaces.Planning.RequirementDirectory do
  @moduledoc "Authorized semantic current-requirement ledger for host composition."
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.ContactRequirements
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.ContactRequirementList
  @states %{"all" => nil, "active" => :active, "closed" => :closed, "canceled" => :canceled}

  def load(scope, mission_id, params) do
    with true <- is_nil(scope.mission_id) or scope.mission_id == mission_id,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, query} <- ContactRequirementList.admit_query(params),
         {:ok, result} <-
           ContactRequirements.list_page(
             scope.organization_id,
             mission_id,
             query.page,
             Map.fetch!(@states, query.state)
           ) do
      {:ok,
       %{
         contract_version: 1,
         context: %{organization_id: scope.organization_id, mission_id: mission_id},
         query: query,
         requirements: %{
           page: query.page,
           more: result.more?,
           entries: Enum.map(result.entries, &row/1)
         }
       }}
    else
      false -> {:error, :scope_mismatch}
      error -> error
    end
  end

  defp row({requirement, version}) do
    %{
      id: requirement.contact_requirement_id,
      version: version.version,
      state: Atom.to_string(requirement.lifecycle_state),
      priority: Atom.to_string(version.priority),
      direction: Atom.to_string(version.service_direction),
      intent: version.contact_intent,
      earliest_start: DateTime.to_iso8601(version.earliest_start),
      latest_end: DateTime.to_iso8601(version.latest_end),
      success_measure: Atom.to_string(version.success_measure),
      minimum_duration_seconds: version.minimum_duration_seconds,
      minimum_data_volume_bytes: version.minimum_data_volume_bytes,
      contact_count: version.contact_count,
      minimum_separation_seconds: version.minimum_separation_seconds
    }
  end
end
