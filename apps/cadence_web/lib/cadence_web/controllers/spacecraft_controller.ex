defmodule CadenceWeb.SpacecraftController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.CommsJSON, as: CommsJSON

  alias Cadence.Spacecraft
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      spacecraft =
        Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id)
        |> Enum.map(&CommsJSON.spacecraft/1)

      json(conn, %{data: spacecraft})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "spacecraft_id" => spacecraft_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %Spacecraft{} = spacecraft} <-
           Cadence.SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      json(conn, %{data: CommsJSON.spacecraft(spacecraft)})
    end
  end
end
