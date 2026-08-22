defmodule Cadence.GroundStations do
  @moduledoc """
  Context facade for ground station profiles.

  Delegates:
  - `Cadence.Application.GroundStations.GroundStationProfileQueries` for read operations
  - `Cadence.Application.GroundStations.GroundStationProfileOperations` for write operations
  """

  alias Cadence.Application.GroundStations.{
    GroundStationProfileOperations,
    GroundStationProfileQueries
  }

  alias Cadence.GroundStations.GroundStationProfile

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec list_profiles(organization_id(), keyword()) :: [GroundStationProfile.t()]
  def list_profiles(organization_id, opts \\ []) do
    GroundStationProfileQueries.list(organization_id, opts)
  end

  @spec list_enabled_profiles(mission_id()) :: [GroundStationProfile.t()]
  def list_enabled_profiles(mission_id) do
    GroundStationProfileQueries.list_enabled_for_mission(mission_id)
  end

  @spec get_profile(String.t(), organization_id(), mission_id()) ::
          {:ok, GroundStationProfile.t()} | {:error, :not_found}
  def get_profile(id, organization_id, mission_id) do
    GroundStationProfileQueries.find_for_mission(id, organization_id, mission_id)
  end

  @spec create_profile(organization_id(), mission_id(), map()) ::
          {:ok, GroundStationProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_profile(organization_id, mission_id, attrs) do
    GroundStationProfileOperations.create(organization_id, mission_id, attrs)
  end

  @spec update_profile(organization_id(), mission_id(), GroundStationProfile.t(), map()) ::
          {:ok, GroundStationProfile.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_profile(organization_id, mission_id, %GroundStationProfile{} = profile, attrs) do
    if profile.organization_id == organization_id and profile.mission_id == mission_id do
      GroundStationProfileOperations.update(profile, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @spec delete_profile(organization_id(), mission_id(), GroundStationProfile.t()) ::
          {:ok, GroundStationProfile.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_profile(organization_id, mission_id, %GroundStationProfile{} = profile) do
    if profile.organization_id == organization_id and profile.mission_id == mission_id do
      GroundStationProfileOperations.delete(profile)
    else
      {:error, :unauthorized}
    end
  end
end
