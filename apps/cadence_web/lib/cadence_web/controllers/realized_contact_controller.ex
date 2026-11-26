defmodule CadenceWeb.RealizedContactController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.ContactJSON, as: ContactJSON

  alias CadenceWeb.ControlPlaneAccess

  def runtime(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "realized_contact_id" => realized_contact_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, runtime_snapshot} <-
           Cadence.Runtime.realized_contact_snapshot(mission_id, realized_contact_id) do
      json(conn, %{
        data: ContactJSON.realized_contact_runtime_snapshot(runtime_snapshot)
      })
    end
  end

  def path_runtime(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "realized_contact_id" => realized_contact_id,
        "path_id" => path_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, runtime_snapshot} <-
           Cadence.Runtime.path_runtime_snapshot(mission_id, realized_contact_id, path_id) do
      json(conn, %{data: ContactJSON.path_runtime_snapshot(runtime_snapshot)})
    end
  end
end
