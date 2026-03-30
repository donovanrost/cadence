defmodule CadenceWeb.MissionEventController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ControlPlaneParams.mission_event_filters(params) do
      mission_events =
        Cadence.list_mission_events(organization_id, mission_id, opts)
        |> Enum.map(&ControlPlaneJSON.mission_event(organization_id, &1))

      json(conn, %{data: mission_events})
    end
  end
end
