defmodule Cadence.SpacecraftStore do
  @moduledoc """
  Persistence boundary for mission-owned spacecraft.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Missions
  alias Cadence.Persistence.Schemas.{SourceEndpointRow, SpacecraftRow}
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

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
  end

  @spec fetch_spacecraft(binary(), binary()) :: {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(mission_id, spacecraft_id)
      when is_binary(mission_id) and is_binary(spacecraft_id) do
    case Repo.get_by(SpacecraftRow, mission_id: mission_id, spacecraft_id: spacecraft_id) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, SpacecraftRow.to_domain(row)}
    end
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

  @spec fetch_spacecraft_by_scid(binary(), non_neg_integer()) ::
          {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft_by_scid(mission_id, scid)
      when is_binary(mission_id) and is_integer(scid) and scid >= 0 do
    case Repo.get_by(SpacecraftRow, mission_id: mission_id, scid: scid) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, SpacecraftRow.to_domain(row)}
    end
  end

  @spec fetch_spacecraft_by_scid(binary(), binary(), non_neg_integer()) ::
          {:ok, Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft_by_scid(organization_id, mission_id, scid)
      when is_binary(organization_id) and is_binary(mission_id) and is_integer(scid) and scid >= 0 do
    case Repo.get_by(SpacecraftRow,
           organization_id: organization_id,
           mission_id: mission_id,
           scid: scid
         ) do
      nil -> {:error, :spacecraft_not_found}
      %SpacecraftRow{} = row -> {:ok, SpacecraftRow.to_domain(row)}
    end
  end

  @spec ensure_managed_source_endpoint(binary(), Spacecraft.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def ensure_managed_source_endpoint(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    source_endpoint_id = managed_source_endpoint_id(spacecraft.spacecraft_id)

    case Repo.get_by(SourceEndpointRow,
           organization_id: organization_id,
           mission_id: spacecraft.mission_id,
           source_endpoint_id: source_endpoint_id
         ) do
      %SourceEndpointRow{} = row ->
        update_managed_source_endpoint(row, organization_id, spacecraft, source_endpoint_id)

      nil ->
        persist_managed_source_endpoint(organization_id, spacecraft, source_endpoint_id)
    end
  end

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

  defp managed_source_endpoint_id(spacecraft_id), do: "spacecraft_runtime:" <> spacecraft_id

  defp update_managed_source_endpoint(
         %SourceEndpointRow{} = row,
         organization_id,
         spacecraft,
         source_endpoint_id
       ) do
    source_endpoint =
      managed_source_endpoint(
        organization_id,
        spacecraft,
        source_endpoint_id,
        SourceEndpointRow.to_domain(row).metadata
      )

    case row
         |> SourceEndpointRow.update_changeset(source_endpoint)
         |> Repo.update() do
      {:ok, %SourceEndpointRow{} = updated_row} -> {:ok, SourceEndpointRow.to_domain(updated_row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_managed_source_endpoint(organization_id, spacecraft, source_endpoint_id) do
    source_endpoint =
      managed_source_endpoint(organization_id, spacecraft, source_endpoint_id, %{})

    case Repo.insert(SourceEndpointRow.changeset(source_endpoint),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :source_endpoint_id]
         ) do
      {:ok, %SourceEndpointRow{} = row} -> {:ok, SourceEndpointRow.to_domain(row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_source_endpoint(organization_id, spacecraft, source_endpoint_id, metadata) do
    SourceEndpoint.new(%{
      source_endpoint_id: source_endpoint_id,
      organization_id: organization_id,
      mission_id: spacecraft.mission_id,
      spacecraft_id: spacecraft.spacecraft_id,
      scid: spacecraft.scid,
      display_name: spacecraft.display_name,
      metadata: Map.put(metadata || %{}, "managed_by", "spacecraft")
    })
  end
end
