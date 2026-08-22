defmodule CadenceWeb.MissionEventController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.MissionJSON, as: MissionJSON

  alias CadenceWeb.API.ReadParams, as: ReadParams

  alias Cadence.Reads.MissionEvents, as: MissionEventReads
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ReadParams.mission_event_filters(params) do
      mission_events =
        MissionEventReads.list_for_mission(organization_id, mission_id, opts)
        |> Enum.map(&MissionJSON.mission_event(organization_id, &1))

      json(conn, %{data: mission_events})
    end
  end
end
