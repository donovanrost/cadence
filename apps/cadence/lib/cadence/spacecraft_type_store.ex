defmodule Cadence.SpacecraftTypeStore do
  @moduledoc """
  Persistence boundary for mission-owned spacecraft types.

  Spacecraft types are versioned: each `persist_spacecraft_type/2` call inserts
  a new row keyed by `(mission_id, spacecraft_type_id, version)`. The latest
  active version is what `fetch_spacecraft_type/2` and `list_spacecraft_types/2`
  return; older versions remain queryable via the explicit version-keyed
  fetchers.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore.SpacecraftTypeRow

  @max_batch_size 100

  @spec persist_spacecraft_type(binary(), SpacecraftType.t()) ::
          {:ok, SpacecraftType.t()} | {:error, term()}
  def persist_spacecraft_type(organization_id, %SpacecraftType{} = type)
      when is_binary(organization_id) do
    with {:ok, scoped_type} <- put_organization_scope(type, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(scoped_type.organization_id, scoped_type.mission_id),
         {:ok, _row} <-
           Repo.insert(SpacecraftTypeRow.changeset(scoped_type),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :spacecraft_type_id, :version]
           ) do
      fetch_spacecraft_type_version(
        scoped_type.organization_id,
        scoped_type.mission_id,
        scoped_type.spacecraft_type_id,
        scoped_type.version
      )
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_spacecraft_type(binary(), binary(), binary()) ::
          {:ok, SpacecraftType.t()} | {:error, term()}
  def fetch_spacecraft_type(organization_id, mission_id, spacecraft_type_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_type_id) do
    case latest_versioned_row(organization_id, mission_id, spacecraft_type_id) do
      nil ->
        {:error, :spacecraft_type_not_found}

      %SpacecraftTypeRow{lifecycle_state: "deleted"} ->
        {:error, :spacecraft_type_not_found}

      %SpacecraftTypeRow{} = row ->
        {:ok, SpacecraftTypeRow.to_domain(row)}
    end
  end

  @spec fetch_spacecraft_type_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, SpacecraftType.t()} | {:error, term()}
  def fetch_spacecraft_type_version(organization_id, mission_id, spacecraft_type_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_type_id) and is_integer(version) and version > 0 do
    case Repo.get_by(SpacecraftTypeRow,
           organization_id: organization_id,
           mission_id: mission_id,
           spacecraft_type_id: spacecraft_type_id,
           version: version
         ) do
      nil -> {:error, :spacecraft_type_not_found}
      %SpacecraftTypeRow{} = row -> {:ok, SpacecraftTypeRow.to_domain(row)}
    end
  end

  @doc "Fetches explicit spacecraft type versions for one bounded batch in one query."
  @spec fetch_spacecraft_type_versions(binary(), binary(), [{binary(), pos_integer()}]) ::
          {:ok, %{optional({binary(), pos_integer()}) => SpacecraftType.t()}}
          | {:error, :batch_bounds_exceeded}
  def fetch_spacecraft_type_versions(organization_id, mission_id, references)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(references) do
    case bounded_references(references) do
      {:error, reason} ->
        {:error, reason}

      {:ok, []} ->
        {:ok, %{}}

      {:ok, references} ->
        predicate =
          Enum.reduce(references, dynamic(false), fn {type_id, version}, acc ->
            dynamic(
              [row],
              ^acc or
                (row.spacecraft_type_id == ^type_id and row.version == ^version)
            )
          end)

        rows =
          SpacecraftTypeRow
          |> where(
            [row],
            row.organization_id == ^organization_id and row.mission_id == ^mission_id
          )
          |> where(^predicate)
          |> Repo.all()

        {:ok,
         Map.new(rows, fn row ->
           {{row.spacecraft_type_id, row.version}, SpacecraftTypeRow.to_domain(row)}
         end)}
    end
  end

  defp bounded_references(references) do
    references = Enum.take(references, @max_batch_size + 1)

    cond do
      length(references) > @max_batch_size ->
        {:error, :batch_bounds_exceeded}

      not Enum.all?(references, &valid_reference?/1) ->
        {:error, :batch_bounds_exceeded}

      true ->
        {:ok, Enum.uniq(references)}
    end
  end

  @spec list_spacecraft_types(binary(), binary()) :: [SpacecraftType.t()]
  def list_spacecraft_types(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftTypeRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.spacecraft_type_id, desc: row.version)
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.spacecraft_type_id, row) end)
    |> Map.values()
    |> Enum.reject(&(&1.lifecycle_state == "deleted"))
    |> Enum.sort_by(& &1.display_name)
    |> Enum.map(&SpacecraftTypeRow.to_domain/1)
  end

  @spec list_spacecraft_type_versions(binary(), binary(), binary()) :: [SpacecraftType.t()]
  def list_spacecraft_type_versions(organization_id, mission_id, spacecraft_type_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_type_id) do
    SpacecraftTypeRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.spacecraft_type_id == ^spacecraft_type_id
    )
    |> order_by([row], desc: row.version)
    |> Repo.all()
    |> Enum.map(&SpacecraftTypeRow.to_domain/1)
  end

  defp latest_versioned_row(organization_id, mission_id, spacecraft_type_id) do
    SpacecraftTypeRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.spacecraft_type_id == ^spacecraft_type_id
    )
    |> order_by([row], desc: row.version)
    |> limit(1)
    |> Repo.one()
  end

  defp valid_reference?({type_id, version}),
    do: is_binary(type_id) and type_id != "" and is_integer(version) and version > 0

  defp valid_reference?(_reference), do: false

  defp put_organization_scope(%SpacecraftType{} = type, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case type.organization_id do
      nil ->
        {:ok, %SpacecraftType{type | organization_id: organization_id}}

      ^organization_id ->
        {:ok, type}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          type.mission_id}}
    end
  end
end
