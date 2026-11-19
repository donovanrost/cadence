defmodule Cadence.ContactPlanning.RepairLinks do
  @moduledoc """
  Repair runs as links between plans (`RepairChain`): each run that proposed a candidate plan
  from a source plan, with the pairing it persisted (`result_summary_document["replaces"]`,
  `%{new snapshot_id => lost key}`) and the lost bookings single bookings cover
  (`"covered"`, `%{lost key => provider_reservation_id}`, #56), oldest first.
  """

  import Ecto.Query

  alias Cadence.Management.Contacts.Store.FleetPlanningRunRow
  alias Cadence.Repo

  @spec list(binary(), binary()) :: [
          %{
            run_id: binary(),
            source: binary(),
            plan_id: binary(),
            replaces: map(),
            covered: map()
          }
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
    |> Enum.map(&Map.merge(&1, %{replaces: replaces(&1.replaces), covered: covered(&1.replaces)}))
  end

  defp replaces(%{"replaces" => replaces}) when is_map(replaces), do: replaces
  defp replaces(_summary), do: %{}

  defp covered(%{"covered" => covered}) when is_map(covered), do: covered
  defp covered(_summary), do: %{}

  @doc "Persists a repair run's pairing (`RepairChain.backfill/2` for runs that predate it)."
  @spec put_replaces(binary(), map()) :: :ok | {:error, term()}
  def put_replaces(run_id, replaces) do
    row = Repo.get!(FleetPlanningRunRow, run_id)
    summary = Map.put(row.result_summary_document || %{}, "replaces", replaces)

    case row |> Ecto.Changeset.change(result_summary_document: summary) |> Repo.update() do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
