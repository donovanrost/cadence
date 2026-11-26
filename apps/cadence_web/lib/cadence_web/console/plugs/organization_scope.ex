defmodule CadenceWeb.Console.Plugs.OrganizationScope do
  @moduledoc """
  For `/api/v1/organizations/:organization_id/...` routes: rebinds
  `current_scope` to that organization (the URL decides, not the session's
  default). Controllers still authorize each action through their facade;
  an actor with no access to the organization gets `404 organization_not_found`.
  """

  import Plug.Conn

  alias Cadence.Auth.Policy
  alias CadenceWeb.Console.{Access, Problem}

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"organization_id" => organization_id}} = conn, _opts) do
    credentials = %{conn.assigns.console_credentials | current_organization_id: organization_id}

    with {:ok, scope} <- Access.authenticate(credentials),
         :ok <-
           Policy.authorize(scope, :operate_organization, %{organization_id: organization_id}) do
      assign(conn, :current_scope, scope)
    else
      {:error, :unauthenticated} -> Problem.respond(conn, :unauthenticated)
      {:error, _denied} -> Problem.respond(conn, :organization_not_found)
    end
  end

  def call(conn, _opts), do: Problem.respond(conn, :organization_not_found)
end
