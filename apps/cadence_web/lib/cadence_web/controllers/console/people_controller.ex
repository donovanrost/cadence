defmodule CadenceWeb.Console.PeopleController do
  @moduledoc """
  Organization people and invitations under
  `/api/console/v1/organizations/:organization_id`. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.OrganizationPeople
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, %{"organization_id" => organization_id}) do
    case OrganizationPeople.load(conn.assigns.current_scope, organization_id) do
      {:ok, people} -> json(conn, %{data: ConfigJSON.encode(people)})
      {:error, reason} -> Problem.respond(conn, reason)
    end
  end

  def service_identities(conn, %{"organization_id" => organization_id}) do
    case OrganizationPeople.service_identities(conn.assigns.current_scope, organization_id) do
      {:ok, data} -> json(conn, %{data: ConfigJSON.encode(data)})
      {:error, reason} -> Problem.respond(conn, reason)
    end
  end

  def invite(conn, %{"organization_id" => organization_id} = params) do
    case OrganizationPeople.invite(conn.assigns.current_scope, organization_id, params) do
      {:ok, invitation} ->
        conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(invitation)})

      {:error, {:invalid, details}} ->
        Problem.respond(conn, :invalid_params, details)

      {:error, reason} ->
        Problem.respond(conn, reason)
    end
  end
end
