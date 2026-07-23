defmodule CadenceWeb.CommandApprovalController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandApproval
  alias Cadence.Management.Commanding
  alias CadenceWeb.ControlPlaneAccess
  alias CadenceWeb.ControlPlaneJSON.Commanding, as: CommandingJSON
  alias CadenceWeb.ControlPlaneParams.Commanding, as: CommandingParams

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CommandingParams.command_approval_filters(params) do
      command_approvals =
        Commanding.list_command_approvals(
          organization_id,
          mission_id,
          filters
        )
        |> Enum.map(&CommandingJSON.command_approval/1)

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
           Commanding.fetch_command_approval(
             organization_id,
             mission_id,
             command_approval_id
           ) do
      json(conn, %{data: CommandingJSON.command_approval(command_approval)})
    end
  end
end
