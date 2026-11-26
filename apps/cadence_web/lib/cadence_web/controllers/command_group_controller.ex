defmodule CadenceWeb.CommandGroupController do
  @moduledoc """
  Command groups for a mission-pinned service identity (#708): the way to command over REST. One
  target and one command is a group of one. The bodies, rules and answers are the console's
  (`CadenceWeb.Console.CommandGroupController`, docs/apogee/api/commanding.md); only the
  credential differs.

  - The requester is the bearer's own service identity, taken from the scope. A body that names
    an actor is refused `actor_not_assignable` (DECISIONS #30).
  - The service must be active and pinned to this mission and organization
    (`:operate_mission`), checked against the path before anything is read.
  - A service's group always needs a person's GO (`CommandPolicy`). There is no decision route
    here: deciding a group is a person's, through the console.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias CadenceWeb.Console.{CommandGroupController, Problem}

  @actor_keys ~w(requested_by actor actor_kind user_id service_identity_id decided_by
                 requested_by_user_id sent_back_from)

  plug :authorize_mission
  plug :no_actor_in_body when action in [:preflight, :create]

  defdelegate preflight(conn, params), to: CommandGroupController
  defdelegate create(conn, params), to: CommandGroupController
  defdelegate index(conn, params), to: CommandGroupController
  defdelegate show(conn, params), to: CommandGroupController

  defp authorize_mission(conn, _opts) do
    %{"organization_id" => org, "mission_id" => mission} = conn.params

    with :ok <-
           Policy.authorize(conn.assigns.current_scope, :operate_mission, %{
             organization_id: org,
             mission_id: mission
           }),
         {:ok, mission} <- Cadence.Missions.fetch_mission(org, mission) do
      assign(conn, :current_mission, mission)
    else
      {:error, :scope_mismatch} -> conn |> Problem.respond(:scope_mismatch) |> halt()
      {:error, :mission_not_found} -> conn |> Problem.respond(:mission_not_found) |> halt()
      _other -> conn |> Problem.respond(:forbidden) |> halt()
    end
  end

  defp no_actor_in_body(conn, _opts) do
    case Enum.filter(@actor_keys, &Map.has_key?(conn.body_params, &1)) do
      [] -> conn
      keys -> conn |> Problem.respond(:actor_not_assignable, %{fields: keys}) |> halt()
    end
  end
end
