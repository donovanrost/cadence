defmodule Cadence.Application.GroundStations.GroundStationProfileOperations do
  @moduledoc """
  Write operations for ground station profiles.
  """

  alias Cadence.Application.Missions.MissionOperations
  alias Cadence.GroundStations.GroundStationProfile
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec create(organization_id(), mission_id(), map()) ::
          {:ok, GroundStationProfile.t()} | {:error, Ecto.Changeset.t()}
  def create(organization_id, mission_id, attrs) do
    attrs =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:mission_id, mission_id)

    %GroundStationProfile{}
    |> GroundStationProfile.changeset(attrs)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update(GroundStationProfile.t(), map()) ::
          {:ok, GroundStationProfile.t()} | {:error, Ecto.Changeset.t()}
  def update(%GroundStationProfile{} = profile, attrs) do
    profile
    |> GroundStationProfile.changeset(attrs)
    |> Repo.update()
    |> maybe_bump_config_generation(profile.mission_id)
  end

  @spec delete(GroundStationProfile.t()) ::
          {:ok, GroundStationProfile.t()} | {:error, Ecto.Changeset.t()}
  def delete(%GroundStationProfile{} = profile) do
    profile
    |> Repo.delete()
    |> maybe_bump_config_generation(profile.mission_id)
  end

  defp maybe_bump_config_generation({:ok, _record} = result, mission_id) do
    _ = MissionOperations.bump_config_generation!(mission_id)
    result
  end

  defp maybe_bump_config_generation(result, _mission_id), do: result
end
