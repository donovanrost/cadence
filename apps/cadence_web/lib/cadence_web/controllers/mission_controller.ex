defmodule CadenceWeb.MissionController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.IdentityJSON, as: IdentityJSON

  alias CadenceWeb.ControlPlaneAccess

  def show(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      json(conn, %{data: IdentityJSON.mission(mission)})
    end
  end
end
