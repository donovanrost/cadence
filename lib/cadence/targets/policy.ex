defmodule Cadence.Targets.Policy do
  @moduledoc """
  Authorization policy for target-level actions.

  Target access is inherited from mission-level permissions.
  Users with mission access automatically have appropriate target access.
  """

  @behaviour Bodyguard.Policy

  alias Cadence.Accounts.User
  alias Cadence.Targets.Target
  alias Cadence.Missions.Mission
  alias Cadence.Repo

  # Authorize based on mission-level permissions
  def authorize(action, %User{} = user, %Target{mission_id: mission_id}) do
    mission = Repo.get(Mission, mission_id)

    if mission do
      Cadence.Missions.Policy.authorize(action, user, mission)
    else
      :error
    end
  end

  def authorize(_, _, _), do: :error
end
