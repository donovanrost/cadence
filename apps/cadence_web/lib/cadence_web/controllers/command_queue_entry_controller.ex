defmodule CadenceWeb.CommandQueueEntryController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandQueueEntry
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id} = params) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, filters} <- ControlPlaneParams.command_queue_entry_filters(params) do
      command_queue_entries =
        Cadence.Commanding.list_command_queue_entries(organization_id, mission_id, filters)
        |> Enum.map(&ControlPlaneJSON.command_queue_entry/1)

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
           Cadence.Commanding.fetch_command_queue_entry(
             organization_id,
             mission_id,
             command_queue_entry_id
           ) do
      json(conn, %{data: ControlPlaneJSON.command_queue_entry(command_queue_entry)})
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
           ControlPlaneParams.command_release_attempt(
             Map.get(params, "release_attempt", %{}),
             default_released_by: ControlPlaneAccess.actor_document(conn.assigns.current_scope)
           ),
         {:ok, result} <-
           Cadence.Commanding.release_command_queue_entry(
             organization_id,
             mission_id,
             command_queue_entry_id,
             Keyword.fetch!(release_opts, :realized_contact_id),
             Keyword.fetch!(release_opts, :released_by),
             Keyword.drop(release_opts, [:realized_contact_id, :released_by])
           ) do
      json(conn, %{data: ControlPlaneJSON.command_queue_entry_release_result(result)})
    end
  end
end
