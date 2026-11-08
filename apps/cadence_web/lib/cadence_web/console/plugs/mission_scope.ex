defmodule CadenceWeb.Console.Plugs.MissionScope do
  @moduledoc """
  For `/api/console/v1/missions/:mission_id/...` routes: rebinds
  `current_scope` to the mission's organization and assigns `current_mission`,
  or answers 404 `mission_not_found` when the actor cannot operate it.
  """

  import Plug.Conn

  alias CadenceWeb.Console.Access
  alias CadenceWeb.Console.Problem

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"mission_id" => mission_id}} = conn, _opts) do
    case Access.authorize_mission(conn.assigns.console_credentials, mission_id) do
      {:ok, scope, mission} ->
        conn
        |> assign(:current_scope, scope)
        |> assign(:current_mission, mission)

      {:error, reason} ->
        Problem.respond(conn, reason)
    end
  end

  def call(conn, _opts), do: Problem.respond(conn, :mission_not_found)
end
