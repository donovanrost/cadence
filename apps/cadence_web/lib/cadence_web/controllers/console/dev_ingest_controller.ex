defmodule CadenceWeb.Console.DevIngestController do
  @moduledoc """
  Development ingest, a person's tool: `POST /api/console/v1/missions/:mission_id/dev/space_packets`
  and `.../dev/tm_frames` push one packet or frame through the real ingest path and answer with
  what it produced (#780, #747).

  The routes exist only where `CadenceWeb.Console.DevIngestRoutes` mounts them (dev and test; never
  prod). A service identity is denied like everywhere else on the console API
  (`CadenceWeb.Console.ServiceAccess`), and a person needs the session and CSRF.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.Ingress, as: ControlIngress
  alias CadenceWeb.API.{RuntimeIngressParams, TelemetryJSON}
  alias CadenceWeb.Console.Problem

  def space_packet(conn, %{"space_packet" => params}) when is_map(params),
    do: ingest(conn, &RuntimeIngressParams.dev_space_packet_ingress/2, params)

  def space_packet(conn, _params), do: missing(conn, "space_packet")

  def tm_frame(conn, %{"tm_frame" => params}) when is_map(params),
    do: ingest(conn, &RuntimeIngressParams.dev_tm_frame_ingress/2, params)

  def tm_frame(conn, _params), do: missing(conn, "tm_frame")

  defp ingest(conn, parse, params) do
    mission_id = conn.assigns.current_mission.mission_id

    with {:ok, raw_evidence} <- parse.(mission_id, params),
         {:ok, result} <- ControlIngress.process_and_persist(raw_evidence) do
      json(conn, %{data: TelemetryJSON.dev_ingress_result(result)})
    else
      {:error, {:invalid_param, name, reason}} ->
        Problem.respond(conn, :invalid_params, %{name => to_string(reason)})

      {:error, reason} ->
        Problem.respond(conn, :invalid_params, %{ingest: inspect(reason)})
    end
  end

  defp missing(conn, key),
    do: Problem.respond(conn, :invalid_params, %{key => "is required"})
end
