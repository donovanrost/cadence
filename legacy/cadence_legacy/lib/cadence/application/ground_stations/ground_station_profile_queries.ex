defmodule Cadence.Application.GroundStations.GroundStationProfileQueries do
  @moduledoc """
  Read operations for ground station profiles.
  """

  import Ecto.Query

  alias Cadence.GroundStations.GroundStationProfile
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec list(organization_id(), keyword()) :: [GroundStationProfile.t()]
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    enabled = Keyword.get(opts, :enabled)

    GroundStationProfile
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:enabled, enabled)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @spec list_enabled_for_mission(mission_id()) :: [GroundStationProfile.t()]
  def list_enabled_for_mission(mission_id) do
    GroundStationProfile
    |> where([p], p.mission_id == ^mission_id and p.enabled == true)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @spec find(String.t(), organization_id()) ::
          {:ok, GroundStationProfile.t()} | {:error, :not_found}
  def find(id, organization_id) do
    GroundStationProfile
    |> where([p], p.id == ^id and p.organization_id == ^organization_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
  end

  @spec find_for_mission(String.t(), organization_id(), mission_id()) ::
          {:ok, GroundStationProfile.t()} | {:error, :not_found}
  def find_for_mission(id, organization_id, mission_id) do
    GroundStationProfile
    |> where(
      [
        p
      ],
      p.id == ^id and p.organization_id == ^organization_id and p.mission_id == ^mission_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      profile -> {:ok, profile}
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [p], field(p, ^field) == ^value)
end
