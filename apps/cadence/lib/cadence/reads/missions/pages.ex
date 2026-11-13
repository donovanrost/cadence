defmodule Cadence.Reads.Missions.Pages do
  @moduledoc "Authorized host read for the mission overview page."

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.Missions.Overview

  def load(%Scope{} = scope, page, mission_id \\ nil) do
    with :ok <- authorize(scope, page, mission_id),
         {:ok, data} <- read(scope, page, mission_id) do
      JSONBoundary.safe(data)
    end
  end

  defp authorize(scope, "mission_overview", mission_id) when is_binary(mission_id),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })

  defp authorize(_scope, _page, _mission_id), do: {:error, :invalid_mission_page}

  defp read(scope, "mission_overview", mission_id),
    do: Overview.load(scope.organization_id, mission_id)
end
