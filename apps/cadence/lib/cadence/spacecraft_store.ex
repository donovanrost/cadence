defmodule Cadence.SpacecraftStore do
  @moduledoc """
  Persistence boundary for mission-owned spacecraft.
  """

  alias Cadence.Platform.ScopedReadUpdates

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Listing
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore.SpacecraftRow
  alias Cadence.SpacecraftTypeStore

  def fetch_pinned_profile(_mission, %Spacecraft{spacecraft_type_id: nil}), do: {:ok, nil}

  def fetch_pinned_profile(mission, %Spacecraft{
        spacecraft_type_id: type_id,
        spacecraft_type_version: version
      })
      when is_binary(type_id) and is_integer(version) do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           mission.organization_id,
           mission.mission_id,
           type_id,
           version
         ) do
      {:ok, profile} -> {:ok, profile}
      {:error, _reason} -> {:ok, nil}
    end
  end

  def fetch_pinned_profile(_mission, _spacecraft), do: {:ok, nil}

  @max_batch_size 100

  @type list_filter ::
          :missing_profile
          | :missing_scid
          | {:profile, binary()}
          | {:stale_versions, %{optional(binary()) => pos_integer()}}

  @type list_opt ::
          {:search, binary() | nil}
          | {:filter, list_filter() | nil}
          | {:sort, {:display_name | :scid | :spacecraft_id, :asc | :desc}}
          | {:page, pos_integer()}
          | {:page_size, pos_integer()}

  @spec persist_spacecraft(binary(), Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    with {:ok, scoped_spacecraft} <- put_organization_scope(spacecraft, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_spacecraft.organization_id, scoped_spacecraft.mission_id),
         {:ok, _row} <-
           Repo.insert(SpacecraftRow.changeset(scoped_spacecraft),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :spacecraft_id]
           ) do
      {:ok, scoped_spacecraft}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
    |> notify_configuration_change()
  end

  @spec persist_spacecraft(Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(%Spacecraft{} = spacecraft) do
    case Repo.insert(SpacecraftRow.changeset(spacecraft),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :spacecraft_id]
         ) do
      {:ok, %SpacecraftRow{} = row} ->
        {:ok, SpacecraftRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
    |> notify_configuration_change()
  end

  @spec update_spacecraft(binary(), Spacecraft.t()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def update_spacecraft(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    with {:ok, scoped_spacecraft} <- put_organization_scope(spacecraft, organization_id),
         {:ok, %SpacecraftRow{} = row} <-
           fetch_spacecraft_row(
             scoped_spacecraft.organization_id,
             scoped_spacecraft.mission_id,
             scoped_spacecraft.spacecraft_id
           ) do
      case row
           |> SpacecraftRow.update_changeset(scoped_spacecraft)
           |> Repo.update() do
        {:ok, %SpacecraftRow{} = updated_row} -> {:ok, SpacecraftRow.to_domain(updated_row)}
        {:error, %Changeset{} = changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
      end
    end
    |> notify_configuration_change()
  end

  @spec fetch_spacecraft(binary(), binary()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(mission_id, spacecraft_id)
      when is_binary(mission_id) and is_binary(spacecraft_id) do
    case Repo.get_by(SpacecraftRow, mission_id: mission_id, spacecraft_id: spacecraft_id) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, SpacecraftRow.to_domain(row)}
    end
  end

  @doc "Serializes identity and reviewed framing changes against the same current spacecraft."
  def with_locked_spacecraft(organization_id, mission_id, spacecraft_id, operation) do
    Repo.transact(fn ->
      row =
        Repo.one(
          from(row in SpacecraftRow,
            where:
              row.organization_id == ^organization_id and row.mission_id == ^mission_id and
                row.spacecraft_id == ^spacecraft_id,
            lock: "FOR UPDATE"
          )
        )

      case row do
        nil -> {:error, :spacecraft_not_found}
        row -> operation.(SpacecraftRow.to_domain(row))
      end
    end)
    |> ScopedReadUpdates.publish_result(
      :spacecraft_configuration_changed,
      organization_id,
      mission_id
    )
  end

  @spec fetch_spacecraft(binary(), binary(), binary()) ::
          {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    case fetch_spacecraft_row(organization_id, mission_id, spacecraft_id) do
      {:ok, %SpacecraftRow{} = row} -> {:ok, SpacecraftRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetches at most one bounded batch of mission spacecraft in one query."
  @spec fetch_spacecrafts(binary(), binary(), [binary()]) ::
          {:ok, %{optional(binary()) => Spacecraft.t()}} | {:error, :batch_bounds_exceeded}
  def fetch_spacecrafts(organization_id, mission_id, spacecraft_ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft_ids) do
    case bounded_spacecraft_ids(spacecraft_ids) do
      {:error, reason} ->
        {:error, reason}

      {:ok, []} ->
        {:ok, %{}}

      {:ok, ids} ->
        rows =
          SpacecraftRow
          |> where(
            [row],
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.spacecraft_id in ^ids
          )
          |> Repo.all()

        {:ok, Map.new(rows, fn row -> {row.spacecraft_id, SpacecraftRow.to_domain(row)} end)}
    end
  end

  @doc "Curated display names for a bounded set of mission spacecraft; no metadata is loaded."
  def display_names(organization_id, mission_id, spacecraft_ids) do
    with {:ok, ids} <- bounded_spacecraft_ids(spacecraft_ids) do
      rows =
        Repo.all(
          from(row in SpacecraftRow,
            where:
              row.organization_id == ^organization_id and row.mission_id == ^mission_id and
                row.spacecraft_id in ^ids,
            select: %{"id" => row.spacecraft_id, "name" => row.display_name}
          )
        )

      {:ok, rows}
    end
  end

  @doc "Scoped identity-only subquery for composing paged searches without materializing the fleet."
  def display_name_ids_query(organization_id, mission_id, search) do
    pattern = "%" <> Listing.escape_like(search) <> "%"

    from(row in SpacecraftRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          ilike(row.display_name, ^pattern),
      select: row.spacecraft_id
    )
  end

  defp bounded_spacecraft_ids(spacecraft_ids) do
    ids = Enum.take(spacecraft_ids, @max_batch_size + 1)

    cond do
      length(ids) > @max_batch_size ->
        {:error, :batch_bounds_exceeded}

      not Enum.all?(ids, &(is_binary(&1) and &1 != "")) ->
        {:error, :batch_bounds_exceeded}

      true ->
        {:ok, Enum.uniq(ids)}
    end
  end

  @spec list_spacecraft(binary()) :: [Spacecraft.t()]
  def list_spacecraft(mission_id) when is_binary(mission_id) do
    SpacecraftRow
    |> where([row], row.mission_id == ^mission_id)
    |> order_by([row], asc: row.spacecraft_id)
    |> Repo.all()
    |> Enum.map(&SpacecraftRow.to_domain/1)
  end

  @spec list_spacecraft(binary(), binary()) :: [Spacecraft.t()]
  def list_spacecraft(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.spacecraft_id)
    |> Repo.all()
    |> Enum.map(&SpacecraftRow.to_domain/1)
  end

  @doc "Counts spacecraft across an organization's missions without loading their records."
  def count_organization_spacecraft(organization_id) when is_binary(organization_id) do
    SpacecraftRow
    |> where([row], row.organization_id == ^organization_id)
    |> Repo.aggregate(:count, :spacecraft_id)
  end

  @doc """
  Returns one page of a mission's spacecraft, filtered and sorted.

  Search is `ILIKE` over `display_name` and `scid` cast to text — intentionally
  unindexed: the base query is already narrowed by the indexed
  `(organization_id, mission_id)` scope, and per-mission fleets are expected to
  stay in the hundreds. Revisit (trigram index) only if a mission exceeds ~10k
  spacecraft.
  """
  @spec list_spacecraft_page(binary(), binary(), [list_opt()]) :: Listing.Page.t()
  def list_spacecraft_page(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) do
    %{page: page, page_size: page_size, offset: offset} = Listing.page_opts(opts)

    filtered =
      SpacecraftRow
      |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
      |> apply_search(opts[:search])
      |> apply_filter(opts[:filter])

    items =
      filtered
      |> apply_sort(Keyword.get(opts, :sort, {:spacecraft_id, :asc}))
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&SpacecraftRow.to_domain/1)

    %Listing.Page{
      items: items,
      total_count: Repo.aggregate(filtered, :count),
      page: page,
      page_size: page_size
    }
  end

  @doc """
  Fleet-wide aggregates for a mission's spacecraft, computed in two queries:
  overall/missing counts and per-(profile, version) counts. Drift is derived
  by the caller from `profile_version_counts` against latest active profile
  versions.
  """
  @spec fleet_summary(binary(), binary()) :: %{
          total: non_neg_integer(),
          missing_scid: non_neg_integer(),
          missing_profile: non_neg_integer(),
          profile_version_counts: [
            %{
              spacecraft_type_id: binary(),
              spacecraft_type_version: pos_integer() | nil,
              count: non_neg_integer()
            }
          ]
        }
  def fleet_summary(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    base =
      where(
        SpacecraftRow,
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )

    totals =
      base
      |> select([row], %{
        total: count(row.spacecraft_id),
        missing_scid: filter(count(row.spacecraft_id), is_nil(row.scid)),
        missing_profile: filter(count(row.spacecraft_id), is_nil(row.spacecraft_type_id))
      })
      |> Repo.one()

    profile_version_counts =
      base
      |> where([row], not is_nil(row.spacecraft_type_id))
      |> group_by([row], [row.spacecraft_type_id, row.spacecraft_type_version])
      |> select([row], %{
        spacecraft_type_id: row.spacecraft_type_id,
        spacecraft_type_version: row.spacecraft_type_version,
        count: count(row.spacecraft_id)
      })
      |> Repo.all()

    Map.put(totals, :profile_version_counts, profile_version_counts)
  end

  defp apply_search(query, search) when is_binary(search) and search != "" do
    pattern = "%" <> Listing.escape_like(search) <> "%"

    where(
      query,
      [row],
      ilike(row.display_name, ^pattern) or
        ilike(fragment("CAST(? AS TEXT)", row.scid), ^pattern)
    )
  end

  defp apply_search(query, _search), do: query

  defp apply_filter(query, :missing_profile),
    do: where(query, [row], is_nil(row.spacecraft_type_id))

  defp apply_filter(query, :missing_scid), do: where(query, [row], is_nil(row.scid))

  defp apply_filter(query, {:profile, spacecraft_type_id}),
    do: where(query, [row], row.spacecraft_type_id == ^spacecraft_type_id)

  defp apply_filter(query, {:stale_versions, latest_versions})
       when is_map(latest_versions) do
    condition =
      Enum.reduce(latest_versions, dynamic(false), fn {type_id, latest}, dyn ->
        dynamic(
          [row],
          ^dyn or
            (row.spacecraft_type_id == ^type_id and row.spacecraft_type_version < ^latest)
        )
      end)

    where(query, ^condition)
  end

  defp apply_filter(query, nil), do: query

  defp apply_sort(query, {:display_name, dir}) when dir in [:asc, :desc],
    do: order_by(query, [row], [{^dir, row.display_name}, asc: row.spacecraft_id])

  defp apply_sort(query, {:scid, :asc}),
    do: order_by(query, [row], asc_nulls_last: row.scid, asc: row.spacecraft_id)

  defp apply_sort(query, {:scid, :desc}),
    do: order_by(query, [row], desc_nulls_last: row.scid, asc: row.spacecraft_id)

  defp apply_sort(query, {:spacecraft_id, dir}) when dir in [:asc, :desc],
    do: order_by(query, [row], [{^dir, row.spacecraft_id}])

  defp fetch_spacecraft_row(organization_id, mission_id, spacecraft_id) do
    case Repo.get_by(
           SpacecraftRow,
           organization_id: organization_id,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         ) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, row}
    end
  end

  defp put_organization_scope(%Spacecraft{} = spacecraft, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case spacecraft.organization_id do
      nil ->
        {:ok, %Spacecraft{spacecraft | organization_id: organization_id}}

      ^organization_id ->
        {:ok, spacecraft}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          spacecraft.mission_id}}
    end
  end

  defp notify_configuration_change({:ok, resource} = result),
    do:
      ScopedReadUpdates.publish_result(
        result,
        :spacecraft_configuration_changed,
        resource.organization_id,
        resource.mission_id
      )

  defp notify_configuration_change(result), do: result
end
