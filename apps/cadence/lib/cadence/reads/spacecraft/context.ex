defmodule Cadence.Reads.Spacecraft.Context do
  @moduledoc "Shared, scoped inputs for spacecraft overview and readiness composition."
  alias Cadence.Applications.HostContext
  alias Cadence.Reads.Applications.SpacecraftInventory
  alias Cadence.Reads.Spacecraft.PinnedProfile
  alias Cadence.SpacecraftStore

  def load(scope, mission, id) do
    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(mission.organization_id, mission.mission_id, id),
         {:ok, profile} <- PinnedProfile.load(mission, spacecraft) do
      profile = if profile && profile.lifecycle_state == :active, do: profile, else: nil
      applications = inventory(scope, mission, id, profile)
      {:ok, %{spacecraft: spacecraft, profile: profile, applications: applications}}
    end
  end

  defp inventory(scope, mission, id, profile) do
    SpacecraftInventory.load(
      scope,
      HostContext.spacecraft(mission.mission_id, id),
      if(profile, do: profile.applications, else: %{})
    )
  rescue
    _ -> {:error, :application_inventory_unavailable}
  end
end
