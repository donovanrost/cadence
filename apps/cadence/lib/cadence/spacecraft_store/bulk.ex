defmodule Cadence.SpacecraftStore.Bulk do
  @moduledoc """
  Many spacecraft at once, in a fixed number of statements (#1049): what a change set does to a
  fleet. The one-spacecraft writers in `Cadence.SpacecraftStore` stay for the callers that touch
  one. Each function announces the configuration change once, not per spacecraft.

  Callers run these inside the change-set transaction.
  """

  import Ecto.Query

  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.PassPredictionJobs
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore.SpacecraftRow
  alias Ecto.Changeset

  # Rows an insert carries at 14 columns each stay far under Postgres' 65,535 parameters.
  @insert_chunk 1_000

  @type update :: %{
          spacecraft: Spacecraft.t(),
          switches: %{optional(:commanding_enabled | :telemetry_enabled) => boolean()},
          frees_scid?: boolean()
        }

  @doc """
  Who holds each SCID of `scids` in the mission, archived spacecraft included (an archived
  spacecraft keeps its SCID): `%{scid => spacecraft_id}`. The unique index makes it one holder each.
  """
  @spec scid_holders(binary(), binary(), [non_neg_integer()]) :: %{
          non_neg_integer() => binary()
        }
  def scid_holders(_organization_id, _mission_id, []), do: %{}

  def scid_holders(organization_id, mission_id, scids) when is_list(scids) do
    scids = Enum.uniq(scids)

    from(row in SpacecraftRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.scid in ^scids,
      select: {row.scid, row.spacecraft_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The OTHER missions of the organization with an active spacecraft flying each of `scids` (the
  same-SCID HOLD, ux U81 §1): `%{scid => [mission_id]}`, missions by id, a SCID nobody else flies
  left out. Never across organizations.
  """
  @spec missions_flying_scids(binary(), [non_neg_integer()], binary()) :: %{
          non_neg_integer() => [binary()]
        }
  def missions_flying_scids(_organization_id, [], _except_mission_id), do: %{}

  def missions_flying_scids(organization_id, scids, except_mission_id) when is_list(scids) do
    scids = Enum.uniq(scids)

    from(row in SpacecraftRow,
      where:
        row.organization_id == ^organization_id and row.scid in ^scids and
          row.mission_id != ^except_mission_id and row.lifecycle_state == "active",
      distinct: true,
      order_by: [asc: row.scid, asc: row.mission_id],
      select: {row.scid, row.mission_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Inserts new spacecraft (switches included). `{:error, id, changeset}` names the first one the row
  rules refuse, with nothing inserted. An id that already exists is refused with `:entity_exists`
  (someone wrote it outside the change set between its check and this write), never recorded as
  this change's create.
  """
  @spec insert(binary(), binary(), [Spacecraft.t()]) ::
          {:ok, [Spacecraft.t()]} | {:error, binary(), term()}
  def insert(_organization_id, _mission_id, []), do: {:ok, []}

  def insert(organization_id, mission_id, spacecraft) do
    now = DateTime.utc_now()

    with {:ok, _mission} <- mission(organization_id, mission_id),
         {:ok, rows} <- insert_rows(spacecraft, organization_id, now),
         :ok <- all_inserted(spacecraft, insert_chunks(rows)) do
      announce(organization_id, mission_id)
      {:ok, spacecraft}
    else
      {:error, id, reason} -> {:error, id, reason}
      {:error, reason} -> {:error, first_id(spacecraft), reason}
    end
  end

  @doc """
  Updates spacecraft in place: identity, profile pin, metadata and any switch the update sets.
  A spacecraft that gives up or changes its SCID has it cleared first, so SCIDs that move between
  spacecraft of one change never meet in the unique index half way. Returns the rows as stored.
  """
  @spec update(binary(), binary(), [update()]) ::
          {:ok, [Spacecraft.t()]} | {:error, binary(), term()}
  def update(_organization_id, _mission_id, []), do: {:ok, []}

  def update(organization_id, mission_id, updates) do
    with :ok <-
           check_rows(updates, &SpacecraftRow.update_changeset(%SpacecraftRow{}, &1.spacecraft)),
         :ok <- clear_scids(organization_id, mission_id, updates),
         {:ok, stored} <- write_updates(organization_id, mission_id, updates) do
      announce(organization_id, mission_id)
      {:ok, stored}
    end
  end

  @doc """
  Archives spacecraft (#49/#50) and stages their pass-prediction runs once. The rows are locked in
  id order, so a one-row locker taking them in that order can't deadlock with it.
  """
  @spec archive(binary(), binary(), [binary()], map()) ::
          :ok | {:error, binary(), :spacecraft_not_found}
  def archive(_organization_id, _mission_id, [], _actor), do: :ok

  def archive(organization_id, mission_id, ids, actor) do
    ids = Enum.uniq(ids)

    locked =
      from(row in SpacecraftRow,
        where:
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.spacecraft_id in ^ids,
        order_by: [asc: row.spacecraft_id],
        select: row.spacecraft_id,
        lock: "FOR UPDATE"
      )
      |> Repo.all()

    case Enum.find(ids, &(&1 not in locked)) do
      nil ->
        from(row in SpacecraftRow,
          where:
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.spacecraft_id in ^ids
        )
        |> Repo.update_all(
          set: [lifecycle_state: "archived", archived_at: DateTime.utc_now(), archived_by: actor]
        )

        {:ok, _job} = PassPredictionJobs.stage_spacecraft(organization_id, mission_id, ids)
        :ok

      missing ->
        {:error, missing, :spacecraft_not_found}
    end
  end

  defp mission(organization_id, mission_id),
    do: Missions.fetch_mission(organization_id, mission_id)

  defp insert_rows(spacecraft, organization_id, now) do
    Enum.reduce_while(spacecraft, {:ok, []}, fn %Spacecraft{} = craft, {:ok, rows} ->
      changeset = SpacecraftRow.changeset(%{craft | organization_id: organization_id})

      if changeset.valid?,
        do: {:cont, {:ok, [insert_row(changeset, craft, now) | rows]}},
        else: {:halt, {:error, craft.spacecraft_id, changeset}}
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp insert_row(changeset, craft, now) do
    changeset
    |> Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.merge(%{
      commanding_enabled: craft.commanding_enabled,
      telemetry_enabled: craft.telemetry_enabled,
      inserted_at: now
    })
  end

  # The ids the rows really created: a conflicting id inserts nothing.
  defp insert_chunks(rows) do
    rows
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.flat_map(fn chunk ->
      {_count, inserted} =
        Repo.insert_all(SpacecraftRow, chunk,
          on_conflict: :nothing,
          conflict_target: [:mission_id, :spacecraft_id],
          returning: [:spacecraft_id]
        )

      Enum.map(inserted, & &1.spacecraft_id)
    end)
  end

  defp all_inserted(spacecraft, inserted) do
    inserted = MapSet.new(inserted)

    case Enum.find(spacecraft, &(not MapSet.member?(inserted, &1.spacecraft_id))) do
      nil -> :ok
      %Spacecraft{spacecraft_id: id} -> {:error, id, :entity_exists}
    end
  end

  defp check_rows(items, changeset_of) do
    Enum.find_value(items, :ok, fn %{spacecraft: craft} = item ->
      changeset = changeset_of.(item)
      if changeset.valid?, do: nil, else: {:error, craft.spacecraft_id, changeset}
    end)
  end

  defp clear_scids(organization_id, mission_id, updates) do
    case for(%{frees_scid?: true, spacecraft: craft} <- updates, do: craft.spacecraft_id) do
      [] ->
        :ok

      ids ->
        from(row in SpacecraftRow,
          where:
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.spacecraft_id in ^ids
        )
        |> Repo.update_all(set: [scid: nil])

        :ok
    end
  end

  defp write_updates(organization_id, mission_id, updates) do
    ids = for %{spacecraft: craft} <- updates, do: craft.spacecraft_id

    stored =
      organization_id
      |> update_query(mission_id, updates)
      |> Repo.update_all([])
      |> elem(1)
      |> Map.new(&{&1.spacecraft_id, SpacecraftRow.to_domain(&1)})

    case Enum.find(ids, &(not Map.has_key?(stored, &1))) do
      nil -> {:ok, Enum.map(ids, &Map.fetch!(stored, &1))}
      missing -> {:error, missing, :spacecraft_not_found}
    end
  end

  # One statement over the rows to set, in the order given (a switch left nil keeps the column).
  defp update_query(organization_id, mission_id, updates) do
    ids = column(updates, :spacecraft_id)
    names = column(updates, :display_name)
    scids = column(updates, :scid)
    types = column(updates, :spacecraft_type_id)
    versions = column(updates, :spacecraft_type_version)
    commanding = Enum.map(updates, &Map.get(&1.switches, :commanding_enabled))
    telemetry = Enum.map(updates, &Map.get(&1.switches, :telemetry_enabled))

    metadata =
      Enum.map(updates, &(&1.spacecraft.metadata |> JsonDocument.wrap_value() |> Jason.encode!()))

    from(row in SpacecraftRow,
      join:
        set in fragment(
          """
          SELECT * FROM unnest(?::text[], ?::text[], ?::int[], ?::text[], ?::int[], ?::text[],
                               ?::boolean[], ?::boolean[])
            AS t(spacecraft_id, display_name, scid, type_id, type_version, metadata,
                 commanding, telemetry)
          """,
          type(^ids, {:array, :string}),
          type(^names, {:array, :string}),
          type(^scids, {:array, :integer}),
          type(^types, {:array, :string}),
          type(^versions, {:array, :integer}),
          type(^metadata, {:array, :string}),
          type(^commanding, {:array, :boolean}),
          type(^telemetry, {:array, :boolean})
        ),
      on: set.spacecraft_id == row.spacecraft_id,
      where: row.organization_id == ^organization_id and row.mission_id == ^mission_id,
      select: row,
      update: [
        set: [
          display_name: set.display_name,
          scid: set.scid,
          spacecraft_type_id: set.type_id,
          spacecraft_type_version: set.type_version,
          metadata: fragment("?::jsonb", set.metadata),
          commanding_enabled: fragment("COALESCE(?, ?)", set.commanding, row.commanding_enabled),
          telemetry_enabled: fragment("COALESCE(?, ?)", set.telemetry, row.telemetry_enabled)
        ]
      ]
    )
  end

  defp column(updates, field), do: Enum.map(updates, &Map.fetch!(&1.spacecraft, field))

  defp first_id([%Spacecraft{spacecraft_id: id} | _]), do: id

  defp announce(organization_id, mission_id),
    do: ScopedReadUpdates.publish(:spacecraft_configuration_changed, organization_id, mission_id)
end
