defmodule CadenceWeb.PacketDefinitionController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      packet_definitions =
        Cadence.list_packet_definitions(organization_id, mission_id)
        |> Enum.map(&ControlPlaneJSON.packet_definition/1)

      json(conn, %{data: packet_definitions})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "packet_definition" => packet_definition_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %PacketDefinition{} = packet_definition} <-
           ControlPlaneParams.packet_definition(
             organization_id,
             mission_id,
             packet_definition_params
           ),
         {:ok, %PacketDefinition{} = persisted_packet_definition} <-
           Cadence.persist_packet_definition(organization_id, packet_definition) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.packet_definition(persisted_packet_definition)})
    end
  end
end
