defmodule CadenceWeb.CommandRequestController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandRequest
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.command_request_filters(params) do
      command_requests =
        Cadence.Management.Commanding.list_command_requests(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.command_request/1)

      json(conn, %{data: command_requests})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_request" => command_request_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandRequest{} = command_request} <-
           ControlPlaneParams.command_request(
             organization_id,
             mission_id,
             command_request_params,
             default_requested_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, %CommandRequest{} = persisted_command_request} <-
           Cadence.Management.Commanding.persist_command_request(
             organization_id,
             command_request
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.command_request(persisted_command_request)})
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
           Cadence.Management.Commanding.fetch_command_request(
             organization_id,
             mission_id,
             command_request_id
           ) do
      json(conn, %{data: ControlPlaneJSON.command_request(command_request)})
    end
  end

  def approve(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "command_request_id" => command_request_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, approval_opts} <-
           ControlPlaneParams.command_approval(
             command_request_id,
             Map.get(params, "approval", %{}),
             default_decided_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, result} <-
           Cadence.Management.Commanding.approve_command_request(
             organization_id,
             mission_id,
             command_request_id,
             Keyword.fetch!(approval_opts, :decided_by),
             Keyword.drop(approval_opts, [:decided_by])
           ) do
      json(conn, %{data: ControlPlaneJSON.command_request_decision_result(result)})
    end
  end

  def reject(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "command_request_id" => command_request_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, approval_opts} <-
           ControlPlaneParams.command_approval(
             command_request_id,
             Map.get(params, "rejection", %{}),
             default_decided_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, result} <-
           Cadence.Management.Commanding.reject_command_request(
             organization_id,
             mission_id,
             command_request_id,
             Keyword.fetch!(approval_opts, :decided_by),
             Keyword.drop(approval_opts, [:decided_by])
           ) do
      json(conn, %{data: ControlPlaneJSON.command_request_decision_result(result)})
    end
  end

  def enqueue(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "command_request_id" => command_request_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, queue_opts} <-
           ControlPlaneParams.command_queue_entry(
             Map.get(params, "queue_entry", %{}),
             default_enqueued_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, approved_command} <-
           Cadence.Management.Commanding.fetch_approved_command(
             organization_id,
             mission_id,
             command_request_id
           ),
         {:ok, result} <-
           Cadence.Control.Commanding.enqueue(
             approved_command,
             Keyword.fetch!(queue_opts, :enqueued_by),
             Keyword.drop(queue_opts, [:enqueued_by])
           ) do
      json(conn, %{data: ControlPlaneJSON.command_request_enqueue_result(result)})
    end
  end
end
