defmodule CadenceWeb.MissionHealthController do
  alias CadenceWeb.API.MissionJSON, as: MissionJSON

  alias CadenceWeb.API.ReadParams, as: ReadParams

  alias Cadence.Reads.MissionHealth, as: MissionHealthReads
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.ControlPlaneAccess

  def show(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ReadParams.mission_health_filters(params) do
      summary = MissionHealthReads.summary(organization_id, mission_id, opts)

      json(conn, %{data: MissionJSON.mission_health(organization_id, summary)})
    end
  end
end
