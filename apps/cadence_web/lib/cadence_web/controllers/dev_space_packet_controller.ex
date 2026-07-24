defmodule CadenceWeb.DevSpacePacketController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Runtime.Ingress, as: RuntimeIngress

  alias CadenceWeb.API.TelemetryJSON, as: TelemetryJSON

  alias CadenceWeb.API.RuntimeIngressParams, as: RuntimeIngressParams

  alias CadenceWeb.ControlPlaneAccess

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
           RuntimeIngressParams.dev_space_packet_ingress(
             mission_id,
             space_packet_params
           ),
         {:ok, processing_result} <- RuntimeIngress.process_and_persist(raw_evidence) do
      json(conn, %{data: TelemetryJSON.dev_ingress_result(processing_result)})
    end
  end
end
