defmodule Cadence.Management.Contacts.PlanningResults do
  @moduledoc """
  Management-plane persistence boundary for contact-planning execution results.

  Control-plane planners submit domain values through this API; they do not
  depend on management-owned Ecto rows or participate in their transactions.
  """

  import Ecto.Query

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactPlanningRun,
    ContactPlanningSearch
  }

  alias Cadence.Management.Contacts.Store.{
    ContactOpportunitySnapshotRow,
    ContactPlanningRunRow,
    ContactPlanningSearchRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @spec start_run(ContactPlanningRun.t()) :: {:ok, ContactPlanningRun.t()} | {:error, term()}
  def start_run(%ContactPlanningRun{} = run) do
    case Repo.insert(ContactPlanningRunRow.changeset(run)) do
      {:ok, %ContactPlanningRunRow{} = row} -> {:ok, ContactPlanningRunRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_run(binary(), binary(), binary()) ::
          {:ok, ContactPlanningRun.t()} | {:error, :contact_planning_run_not_found}
  def fetch_run(organization_id, mission_id, run_id) do
    case Repo.get_by(ContactPlanningRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_planning_run_id: run_id
         ) do
      nil -> {:error, :contact_planning_run_not_found}
      row -> {:ok, ContactPlanningRunRow.to_domain(row)}
    end
  end

  @spec list_runs(binary(), binary(), binary()) :: [ContactPlanningRun.t()]
  def list_runs(organization_id, mission_id, requirement_id) do
    ContactPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id and
        run.contact_requirement_id == ^requirement_id
    )
    |> order_by([run], desc: run.started_at)
    |> Repo.all()
    |> Enum.map(&ContactPlanningRunRow.to_domain/1)
  end

  @spec list_searches(binary(), binary(), binary()) :: [ContactPlanningSearch.t()]
  def list_searches(organization_id, mission_id, run_id) do
    ContactPlanningSearchRow
    |> where(
      [search],
      search.organization_id == ^organization_id and search.mission_id == ^mission_id and
        search.contact_planning_run_id == ^run_id
    )
    |> order_by([search], asc: search.route_order, asc: search.route_key)
    |> Repo.all()
    |> Enum.map(&ContactPlanningSearchRow.to_domain/1)
  end

  @spec list_snapshots(binary(), binary(), binary()) :: [ContactOpportunitySnapshot.t()]
  def list_snapshots(organization_id, mission_id, run_id) do
    ContactOpportunitySnapshotRow
    |> where(
      [snapshot],
      snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
        snapshot.contact_planning_run_id == ^run_id
    )
    |> order_by([snapshot], asc: snapshot.starts_at, asc: snapshot.provider_opportunity_ref)
    |> Repo.all()
    |> Enum.map(&ContactOpportunitySnapshotRow.to_domain/1)
  end

  @spec complete_run(
          ContactPlanningRun.t(),
          [ContactPlanningSearch.t()],
          [ContactOpportunitySnapshot.t()],
          atom(),
          DateTime.t(),
          map()
        ) :: {:ok, map()} | {:error, term()}
  def complete_run(run, searches, snapshots, lifecycle_state, completed_at, summary) do
    Repo.transaction(fn ->
      persisted_searches = Enum.map(searches, &insert_search!/1)
      persisted_snapshots = Enum.map(snapshots, &insert_snapshot!/1)

      updated_run =
        run.contact_planning_run_id
        |> then(&Repo.get!(ContactPlanningRunRow, &1))
        |> ContactPlanningRunRow.completion_changeset(%{
          lifecycle_state: Atom.to_string(lifecycle_state),
          completed_at: completed_at,
          summary_document: JsonDocument.wrap_value(summary)
        })
        |> Repo.update!()
        |> ContactPlanningRunRow.to_domain()

      %{
        run: updated_run,
        searches: persisted_searches,
        snapshots: Enum.sort_by(persisted_snapshots, &{&1.starts_at, &1.provider_opportunity_ref})
      }
    end)
  rescue
    error in [ArgumentError, Ecto.InvalidChangesetError] ->
      {:error, {:contact_planning_persistence_failed, Exception.message(error)}}
  end

  @spec fail_run(ContactPlanningRun.t(), DateTime.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def fail_run(run, completed_at, summary) do
    case Repo.get(ContactPlanningRunRow, run.contact_planning_run_id) do
      nil ->
        {:error, :contact_planning_run_not_found}

      row ->
        row
        |> ContactPlanningRunRow.completion_changeset(%{
          lifecycle_state: "failed",
          completed_at: completed_at,
          summary_document: JsonDocument.wrap_value(summary)
        })
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:ok,
             %{
               run: ContactPlanningRunRow.to_domain(updated),
               searches: [],
               snapshots: []
             }}

          {:error, update_error} ->
            {:error, {:contact_planning_failure_persistence_failed, update_error}}
        end
    end
  end

  defp insert_search!(search) do
    search
    |> ContactPlanningSearchRow.changeset()
    |> Repo.insert!()
    |> ContactPlanningSearchRow.to_domain()
  end

  defp insert_snapshot!(snapshot) do
    snapshot
    |> ContactOpportunitySnapshotRow.changeset()
    |> Repo.insert!()
    |> ContactOpportunitySnapshotRow.to_domain()
  end
end
