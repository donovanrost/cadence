defmodule Cadence.ContactPlanning.RepairLinks do
  @moduledoc """
  Repair runs as links between plans (`RepairChain`): each run that proposed a candidate plan
  from a source plan, with the pairing it persisted (`result_summary_document["replaces"]`,
  `%{new snapshot_id => lost key}`), oldest first.
  """

  import Ecto.Query

  alias Cadence.Management.Contacts.Store.FleetPlanningRunRow
  alias Cadence.Repo

  @spec list(binary(), binary()) :: [
          %{run_id: binary(), source: binary(), plan_id: binary(), replaces: map()}
        ]
  def list(organization_id, mission_id) do
    FleetPlanningRunRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        not is_nil(r.source_contact_plan_id) and not is_nil(r.candidate_contact_plan_id)
    )
    |> order_by([r], asc: r.inserted_at, asc: r.fleet_planning_run_id)
    |> select([r], %{
      run_id: r.fleet_planning_run_id,
      source: r.source_contact_plan_id,
      plan_id: r.candidate_contact_plan_id,
      replaces: r.result_summary_document
    })
    |> Repo.all()
    |> Enum.map(&%{&1 | replaces: replaces(&1.replaces)})
  end

  defp replaces(%{"replaces" => replaces}) when is_map(replaces), do: replaces
  defp replaces(_summary), do: %{}
end
