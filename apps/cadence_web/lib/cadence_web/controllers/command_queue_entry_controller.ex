defmodule CadenceWeb.CommandQueueEntryController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandQueueEntry
  alias Cadence.Control.Commanding
  alias Cadence.Projections.CommandStatus
  alias CadenceWeb.ControlPlaneAccess
  alias CadenceWeb.ControlPlaneJSON.Commanding, as: CommandingJSON
  alias CadenceWeb.ControlPlaneParams.Commanding, as: CommandingParams

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- CommandingParams.command_queue_entry_filters(params) do
      command_queue_entries =
        CommandStatus.list_queue_entries(
          organization_id,
          mission_id,
          filters
        )
        |> Enum.map(&CommandingJSON.command_queue_entry/1)

      json(conn, %{data: command_queue_entries})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_queue_entry_id" => command_queue_entry_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandQueueEntry{} = command_queue_entry} <-
           CommandStatus.fetch_queue_entry(
             organization_id,
             mission_id,
             command_queue_entry_id
           ) do
      json(conn, %{data: CommandingJSON.command_queue_entry(command_queue_entry)})
    end
  end

  def release(
        conn,
        %{
          "organization_id" => organization_id,
          "mission_id" => mission_id,
          "command_queue_entry_id" => command_queue_entry_id
        } = params
      ) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, release_opts} <-
           CommandingParams.command_release_attempt(
             Map.get(params, "release_attempt", %{}),
             default_released_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, result} <-
           Commanding.release_command_queue_entry(
             organization_id,
             mission_id,
             command_queue_entry_id,
             Keyword.fetch!(release_opts, :realized_contact_id),
             Keyword.fetch!(release_opts, :released_by),
             Keyword.drop(release_opts, [:realized_contact_id, :released_by])
           ) do
      json(conn, %{data: CommandingJSON.command_queue_entry_release_result(result)})
    end
  end
end
