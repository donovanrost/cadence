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

  alias Cadence.Management.Contacts.FleetSnapshotReader

  alias Cadence.Management.Contacts.Store.{
    ContactOpportunitySnapshotRow,
    ContactPlanningRunRow,
    ContactPlanningSearchRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  # The caller commits these immutable results with the fleet requirement checkpoints.
  @doc false
  def insert_fleet_entries(entries) do
    insert_entries(entries, ContactPlanningRunRow, &List.wrap(&1.run), [:inserted_at, :updated_at])

    insert_entries(entries, ContactPlanningSearchRow, & &1.searches, [:inserted_at])

    insert_entries(
      entries,
      ContactOpportunitySnapshotRow,
      &snapshot_rows/1,
      [:inserted_at],
      &Function.identity/1
    )

    :ok
  end

  # An array per column keeps the statement shape fixed and avoids thousands of
  # individual bind parameters. PostgreSQL still validates the ordinary table constraints.
  defp insert_entries(entries, schema, take_records, timestamp_fields, to_row \\ nil) do
    now = DateTime.utc_now() |> DateTime.to_naive()
    fields = schema.__schema__(:fields) -- timestamp_fields
    sql = fleet_insert_sql(schema, fields, timestamp_fields)
    to_row = to_row || (&schema.domain_attrs/1)

    entries
    |> Stream.flat_map(take_records)
    |> Stream.map(to_row)
    |> Stream.chunk_every(2_000)
    |> Enum.each(fn rows ->
      columns = Enum.map(fields, &column_values(rows, &1))
      Repo.query!(sql, columns ++ [now])
    end)
  end

  defp snapshot_rows(entry) do
    readiness = Map.new(entry.searches, &{&1.contact_planning_search_id, &1.readiness_document})

    Enum.map(entry.snapshots, fn snapshot ->
      ContactOpportunitySnapshotRow.compact_attrs(
        snapshot,
        Map.fetch!(readiness, snapshot.contact_planning_search_id)
      )
    end)
  end

  defp fleet_insert_sql(schema, fields, timestamp_fields) do
    arrays =
      fields
      |> Enum.with_index(1)
      |> Enum.map_join(", ", fn {field, index} ->
        "$#{index}::#{column_type(schema.__schema__(:type, field))}[]"
      end)

    timestamps =
      Enum.map_join(timestamp_fields, ", ", fn _ -> "$#{length(fields) + 1}::timestamp" end)

    columns = Enum.join(fields ++ timestamp_fields, ", ")
    table = schema.__schema__(:source)

    "INSERT INTO #{table} (#{columns}) SELECT batch.*, #{timestamps} FROM unnest(#{arrays}) AS batch"
  end

  defp column_values(rows, field) do
    Enum.map(rows, fn row ->
      case Map.fetch!(row, field) do
        %DateTime{} = value -> DateTime.to_naive(value)
        value -> value
      end
    end)
  end

  defp column_type(:string), do: "text"
  defp column_type(:integer), do: "integer"
  defp column_type(:boolean), do: "boolean"
  defp column_type(:map), do: "jsonb"
  defp column_type(:utc_datetime_usec), do: "timestamp"

  @doc false
  def fetch_runs(_organization_id, _mission_id, []), do: %{}

  def fetch_runs(organization_id, mission_id, run_ids) do
    ContactPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id and
        run.contact_planning_run_id in ^run_ids
    )
    |> Repo.all()
    |> Map.new(&{&1.contact_planning_run_id, ContactPlanningRunRow.to_domain(&1)})
  end

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
    list_fleet_snapshots(organization_id, mission_id, [run_id])
  end

  @doc false
  def list_fleet_snapshots(organization_id, mission_id, run_ids) do
    run_ids
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn ids ->
      ContactOpportunitySnapshotRow
      |> where(
        [snapshot],
        snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
          snapshot.contact_planning_run_id in ^ids
      )
      |> order_by([snapshot],
        asc: snapshot.contact_planning_run_id,
        asc: snapshot.starts_at,
        asc: snapshot.provider_opportunity_ref
      )
      |> Repo.all()
      |> Repo.preload(:search)
      |> Enum.map(&ContactOpportunitySnapshotRow.to_domain/1)
    end)
  end

  @doc "Streams compact immutable opportunity snapshots for fleet optimization."
  def stream_fleet_snapshots(organization_id, mission_id, run_ids),
    do: FleetSnapshotReader.stream(organization_id, mission_id, run_ids)

  @doc "Finds the planning runs that supplied selected fleet opportunities."
  def planning_run_ids_for_fleet_snapshots(organization_id, mission_id, snapshot_ids),
    do:
      FleetSnapshotReader.planning_run_ids_for_snapshots(
        organization_id,
        mission_id,
        snapshot_ids
      )

  @doc "A bounded live run ledger; the selected run must be fetched by its exact identity."
  def list_runs_page(organization_id, mission_id, requirement_id, page)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(requirement_id) and
             is_integer(page) and page in 1..1_000_000 do
    ContactPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id and
        run.contact_requirement_id == ^requirement_id
    )
    |> order_by([run], desc: run.started_at, desc: run.contact_planning_run_id)
    |> result_page(page, &ContactPlanningRunRow.to_domain/1)
  end

  def list_runs_page(_, _, _, _), do: {:error, :invalid_planning_result_page}

  @doc "A bounded page of search evidence for one explicitly identified run."
  def list_searches_page(organization_id, mission_id, run_id, page)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(run_id) and
             is_integer(page) and page in 1..1_000_000 do
    ContactPlanningSearchRow
    |> where(
      [search],
      search.organization_id == ^organization_id and search.mission_id == ^mission_id and
        search.contact_planning_run_id == ^run_id
    )
    |> order_by([search],
      asc: search.route_order,
      asc: search.route_key,
      asc: search.contact_planning_search_id
    )
    |> result_page(page, &ContactPlanningSearchRow.to_domain/1)
  end

  def list_searches_page(_, _, _, _), do: {:error, :invalid_planning_result_page}

  @doc "A bounded page of immutable opportunities, including ineligible evidence."
  def list_snapshots_page(organization_id, mission_id, run_id, page)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(run_id) and
             is_integer(page) and page in 1..1_000_000 do
    ContactOpportunitySnapshotRow
    |> where(
      [snapshot],
      snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
        snapshot.contact_planning_run_id == ^run_id
    )
    |> order_by([snapshot],
      asc: snapshot.starts_at,
      asc: snapshot.provider_opportunity_ref,
      asc: snapshot.contact_opportunity_snapshot_id
    )
    |> result_page(page, &ContactOpportunitySnapshotRow.to_domain/1, [:search])
  end

  def list_snapshots_page(_, _, _, _), do: {:error, :invalid_planning_result_page}

  defp result_page(query, page, to_domain, preloads \\ []) do
    rows =
      query |> offset(^((page - 1) * 25)) |> limit(26) |> Repo.all() |> Repo.preload(preloads)

    {:ok, %{entries: rows |> Enum.take(25) |> Enum.map(to_domain), more?: length(rows) > 25}}
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
    |> ContactOpportunitySnapshotRow.to_domain(snapshot.route_binding_document)
  end
end
