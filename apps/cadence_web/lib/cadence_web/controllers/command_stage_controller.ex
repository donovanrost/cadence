defmodule CadenceWeb.CommandStageController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandStage
  alias Cadence.Management.Commanding
  alias CadenceWeb.API.{CommandingJSON, CommandingParams}
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CommandingParams.command_stage_filters(params) do
      command_stages =
        Commanding.list_command_stages(organization_id, mission_id, filters)
        |> Enum.map(&CommandingJSON.command_stage/1)

      json(conn, %{data: command_stages})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_stage" => command_stage_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandStage{} = command_stage} <-
           CommandingParams.command_stage(
             organization_id,
             mission_id,
             command_stage_params,
             default_owner: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, %CommandStage{} = persisted_command_stage} <-
           Commanding.persist_command_stage(organization_id, command_stage) do
      conn
      |> put_status(:created)
      |> json(%{data: CommandingJSON.command_stage(persisted_command_stage)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_stage_id" => command_stage_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandStage{} = command_stage} <-
           Commanding.fetch_command_stage(
             organization_id,
             mission_id,
             command_stage_id
           ) do
      json(conn, %{data: CommandingJSON.command_stage(command_stage)})
    end
  end

  def update(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_stage_id" => command_stage_id,
        "command_stage" => command_stage_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandStage{} = existing_command_stage} <-
           Commanding.fetch_command_stage(
             organization_id,
             mission_id,
             command_stage_id
           ),
         {:ok, %CommandStage{} = updated_command_stage} <-
           CommandingParams.command_stage(existing_command_stage, command_stage_params),
         {:ok, %CommandStage{} = persisted_command_stage} <-
           Commanding.update_command_stage(
             organization_id,
             updated_command_stage
           ) do
      json(conn, %{data: CommandingJSON.command_stage(persisted_command_stage)})
    end
  end

  def submit(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_stage_id" => command_stage_id,
        "submission" => submission_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, {staged_command_item_ids, requested_by}} <-
           CommandingParams.command_stage_submission(
             submission_params,
             default_requested_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, command_requests} <-
           Commanding.submit_staged_command_items(
             organization_id,
             mission_id,
             command_stage_id,
             staged_command_item_ids,
             requested_by
           ) do
      json(conn, %{data: Enum.map(command_requests, &CommandingJSON.command_request/1)})
    end
  end
end
