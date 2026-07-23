defmodule CadenceWeb.CommandReleaseAttemptController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Commanding.CommandReleaseAttempt
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
         {:ok, filters} <- CommandingParams.command_release_attempt_filters(params) do
      command_release_attempts =
        CommandStatus.list_release_attempts(
          organization_id,
          mission_id,
          filters
        )
        |> Enum.map(&CommandingJSON.command_release_attempt/1)

      json(conn, %{data: command_release_attempts})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "command_release_attempt_id" => command_release_attempt_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %CommandReleaseAttempt{} = command_release_attempt} <-
           CommandStatus.fetch_release_attempt(
             organization_id,
             mission_id,
             command_release_attempt_id
           ) do
      json(conn, %{data: CommandingJSON.command_release_attempt(command_release_attempt)})
    end
  end
end
