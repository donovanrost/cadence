defmodule CadenceWeb.CommandVerifierInstanceController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandVerifierInstance
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.command_verifier_instance_filters(params) do
      command_verifier_instances =
        Cadence.Commanding.list_command_verifier_instances(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.command_verifier_instance/1)

      json(conn, %{data: command_verifier_instances})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_verifier_instance_id" => command_verifier_instance_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandVerifierInstance{} = command_verifier_instance} <-
           Cadence.Commanding.fetch_command_verifier_instance(
             organization_id,
             mission_id,
             command_verifier_instance_id
           ) do
      json(conn, %{data: ControlPlaneJSON.command_verifier_instance(command_verifier_instance)})
    end
  end
end
