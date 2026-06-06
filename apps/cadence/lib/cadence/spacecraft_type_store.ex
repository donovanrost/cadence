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
  alias Cadence.Persistence.Schemas.SpacecraftTypeRow
  alias Cadence.Repo
  alias Cadence.SpacecraftType

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
