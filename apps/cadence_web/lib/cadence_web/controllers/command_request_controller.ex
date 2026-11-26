defmodule CadenceWeb.CommandRequestController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Management.Commanding
  alias CadenceWeb.API.{CommandingJSON, CommandingParams}
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CommandingParams.command_request_filters(params) do
      command_requests =
        Commanding.list_command_requests(organization_id, mission_id, filters)
        |> CommandingJSON.encode_all(&CommandingJSON.command_request/2)

      json(conn, %{data: command_requests})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_request_id" => command_request_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandRequest{} = command_request} <-
           Commanding.fetch_command_request(
             organization_id,
             mission_id,
             command_request_id
           ) do
      json(conn, %{data: CommandingJSON.command_request(command_request)})
    end
  end
end
