defmodule Cadence.Reads.OpsWorkspace.Landing do
  @moduledoc "Authorized mission identity and navigation permissions for the Ops workspace."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Missions

  def load(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    resource = %{organization_id: scope.organization_id, mission_id: mission_id}

    with true <- is_nil(scope.mission_id) or scope.mission_id == mission_id,
         :ok <- Policy.authorize(scope, :operate_mission, resource),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id) do
      {:ok,
       %{
         "version" => 1,
         "context" => %{"organization_id" => scope.organization_id, "mission_id" => mission_id},
         "mission_name" => mission.display_name,
         "can_administer" => Policy.authorize(scope, :manage_missions, resource) == :ok
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def load(_, _), do: {:error, :unavailable}
end
