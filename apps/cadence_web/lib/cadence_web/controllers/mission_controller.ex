defmodule CadenceWeb.MissionController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Missions.Mission
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id}) do
    with {:ok, _organization} <-
           ControlPlaneAccess.authorize_organization(
             conn.assigns.current_scope,
             organization_id,
             :manage_missions
           ) do
      missions =
        organization_id
        |> Cadence.list_missions()
        |> Enum.map(&ControlPlaneJSON.mission/1)

      json(conn, %{data: missions})
    end
  end

  def create(conn, %{"organization_id" => organization_id, "mission" => mission_params}) do
    with {:ok, _organization} <-
           ControlPlaneAccess.authorize_organization(
             conn.assigns.current_scope,
             organization_id,
             :manage_missions
           ),
         {:ok, %Mission{} = mission} <-
           ControlPlaneParams.mission(organization_id, mission_params),
         {:ok, %Mission{} = persisted_mission} <- Cadence.persist_mission(mission) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.mission(persisted_mission)})
    end
  end

  def show(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      json(conn, %{data: ControlPlaneJSON.mission(mission)})
    end
  end
end
