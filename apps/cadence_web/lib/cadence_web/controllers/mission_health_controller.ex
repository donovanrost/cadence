defmodule CadenceWeb.MissionHealthController do
  alias Cadence.Reads.MissionHealth, as: MissionHealthReads
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def show(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ControlPlaneParams.mission_health_filters(params) do
      summary = MissionHealthReads.summary(organization_id, mission_id, opts)

      json(conn, %{data: ControlPlaneJSON.mission_health(organization_id, summary)})
    end
  end
end
