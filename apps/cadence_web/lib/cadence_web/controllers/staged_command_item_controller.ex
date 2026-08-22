defmodule CadenceWeb.StagedCommandItemController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandStage
  alias Cadence.Commanding.StagedCommandItem
  alias Cadence.Management.Commanding
  alias CadenceWeb.API.{CommandingJSON, CommandingParams}
  alias CadenceWeb.ControlPlaneAccess

  def index(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "command_stage_id" => command_stage_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandStage{}} <-
           Commanding.fetch_command_stage(
             organization_id,
             mission_id,
             command_stage_id
           ),
         {:ok, filters} <- CommandingParams.staged_command_item_filters(params) do
      staged_command_items =
        filters
        |> Keyword.put(:command_stage_id, command_stage_id)
        |> then(
          &Commanding.list_staged_command_items(
            organization_id,
            mission_id,
            &1
          )
        )
        |> Enum.map(&CommandingJSON.staged_command_item/1)

      json(conn, %{data: staged_command_items})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_stage_id" => command_stage_id,
        "staged_command_item" => staged_command_item_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandStage{}} <-
           Commanding.fetch_command_stage(
             organization_id,
             mission_id,
             command_stage_id
           ),
         {:ok, %StagedCommandItem{} = staged_command_item} <-
           CommandingParams.staged_command_item(
             organization_id,
             mission_id,
             command_stage_id,
             staged_command_item_params
           ),
         {:ok, %StagedCommandItem{} = persisted_staged_command_item} <-
           Commanding.persist_staged_command_item(
             organization_id,
             staged_command_item
           ) do
      conn
      |> put_status(:created)
      |> json(%{data: CommandingJSON.staged_command_item(persisted_staged_command_item)})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "staged_command_item_id" => staged_command_item_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %StagedCommandItem{} = staged_command_item} <-
           Commanding.fetch_staged_command_item(
             organization_id,
             mission_id,
             staged_command_item_id
           ) do
      json(conn, %{data: CommandingJSON.staged_command_item(staged_command_item)})
    end
  end

  def update(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "staged_command_item_id" => staged_command_item_id,
        "staged_command_item" => staged_command_item_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %StagedCommandItem{} = existing_staged_command_item} <-
           Commanding.fetch_staged_command_item(
             organization_id,
             mission_id,
             staged_command_item_id
           ),
         {:ok, %StagedCommandItem{} = updated_staged_command_item} <-
           CommandingParams.staged_command_item(
             existing_staged_command_item,
             staged_command_item_params
           ),
         {:ok, %StagedCommandItem{} = persisted_staged_command_item} <-
           Commanding.update_staged_command_item(
             organization_id,
             updated_staged_command_item
           ) do
      json(conn, %{data: CommandingJSON.staged_command_item(persisted_staged_command_item)})
    end
  end
end
