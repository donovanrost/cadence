defmodule CadenceWeb.CommandApprovalController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandApproval
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.command_approval_filters(params) do
      command_approvals =
        Cadence.list_command_approvals(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.command_approval/1)

      json(conn, %{data: command_approvals})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_approval_id" => command_approval_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandApproval{} = command_approval} <-
           Cadence.fetch_command_approval(organization_id, mission_id, command_approval_id) do
      json(conn, %{data: ControlPlaneJSON.command_approval(command_approval)})
    end
  end
end
