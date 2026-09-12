defmodule Cadence.Reads.Applications.Installations do
  @moduledoc "Authorized core installation inventories, independent of frontend surface registration."
  alias Cadence.Applications.{HostContext, JSONBoundary}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions
  alias Cadence.Reads.Applications.{MissionInstallations, SpacecraftInstallations}

  def load(%Scope{} = scope, %HostContext{placement: placement, mission_id: mission_id} = host)
      when placement in [:mission, :spacecraft] and is_binary(mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, data} <- read(scope, host, mission) do
      JSONBoundary.safe(data)
    end
  rescue
    _error -> {:error, :application_management_unavailable}
  end

  def load(%Scope{}, %HostContext{}), do: {:error, :invalid_application_management_scope}

  defp read(scope, %HostContext{placement: :mission}, mission),
    do: MissionInstallations.load(scope, mission.mission_id)

  defp read(scope, %HostContext{placement: :spacecraft} = host, mission),
    do: SpacecraftInstallations.load(scope, host, mission)
end
