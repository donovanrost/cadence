defmodule CadenceWeb.DevTMFrameController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Runtime.Ingress, as: RuntimeIngress

  alias CadenceWeb.API.TelemetryJSON, as: TelemetryJSON

  alias CadenceWeb.API.RuntimeIngressParams, as: RuntimeIngressParams

  alias CadenceWeb.ControlPlaneAccess

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "tm_frame" => tm_frame_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, raw_evidence} <-
           RuntimeIngressParams.dev_tm_frame_ingress(mission_id, tm_frame_params),
         {:ok, processing_result} <- RuntimeIngress.process_and_persist(raw_evidence) do
      json(conn, %{data: TelemetryJSON.dev_ingress_result(processing_result)})
    end
  end
end
