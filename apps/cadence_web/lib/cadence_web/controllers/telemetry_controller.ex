defmodule CadenceWeb.TelemetryController do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def latest_values(
        conn,
        %{"organization_id" => organization_id, "mission_id" => mission_id} = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ControlPlaneParams.telemetry_latest_filters(params) do
      latest_values =
        TelemetryReads.latest_values_for_mission(organization_id, mission_id, opts)
        |> Enum.map(&ControlPlaneJSON.telemetry_sample/1)

      json(conn, %{data: latest_values})
    end
  end

  def latest_value(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "point_id" => point_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ControlPlaneParams.telemetry_latest_filters(params) do
      latest_value =
        TelemetryReads.latest_value(organization_id, mission_id, point_id, opts)

      json(conn, %{data: latest_value && ControlPlaneJSON.telemetry_sample(latest_value)})
    end
  end

  def history(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "point_id" => point_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, opts} <- ControlPlaneParams.telemetry_history_filters(params) do
      history =
        TelemetryReads.sample_history(organization_id, mission_id, point_id, opts)
        |> Enum.map(&ControlPlaneJSON.telemetry_sample/1)

      json(conn, %{data: history})
    end
  end
end
