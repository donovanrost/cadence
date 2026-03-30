defmodule CadenceWeb.DevSpacePacketController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "space_packet" => space_packet_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, raw_evidence} <-
           ControlPlaneParams.dev_space_packet_ingress(mission_id, space_packet_params),
         {:ok, processing_result} <- Cadence.process_and_persist_telemetry_ingress(raw_evidence) do
      json(conn, %{data: ControlPlaneJSON.dev_ingress_result(processing_result)})
    end
  end
end
