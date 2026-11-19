defmodule CadenceWeb.Console.PeopleController do
  @moduledoc """
  Organization people and invitations under
  `/api/console/v1/organizations/:organization_id`. Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.OrganizationPeople
  alias CadenceWeb.Console.{Capabilities, ConfigJSON, Problem}

  def index(conn, %{"organization_id" => organization_id}) do
    case OrganizationPeople.load(conn.assigns.current_scope, organization_id,
           capabilities: &Capabilities.contributed/1
         ) do
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

  def change_role(conn, %{"organization_id" => organization_id, "user_id" => user_id} = params) do
    conn.assigns.current_scope
    |> OrganizationPeople.change_role(organization_id, user_id, params)
    |> respond(conn, :ok)
  end

  def remove(conn, %{"organization_id" => organization_id, "user_id" => user_id}) do
    conn.assigns.current_scope
    |> OrganizationPeople.remove_member(organization_id, user_id)
    |> respond(conn, :ok)
  end

  def revoke_invitation(conn, %{"organization_id" => org_id, "invitation_id" => id}) do
    case OrganizationPeople.revoke_invitation(conn.assigns.current_scope, org_id, id) do
      :ok -> send_resp(conn, :no_content, "")
      error -> respond(error, conn, :ok)
    end
  end

  def resend_invitation(conn, %{"organization_id" => org_id, "invitation_id" => id}) do
    conn.assigns.current_scope
    |> OrganizationPeople.resend_invitation(org_id, id)
    |> respond(conn, :created)
  end

  defp respond({:ok, data}, conn, status),
    do: conn |> put_status(status) |> json(%{data: ConfigJSON.encode(data)})

  defp respond({:error, {:invalid, details}}, conn, _status),
    do: Problem.respond(conn, :invalid_params, details)

  defp respond({:error, :invalid_role}, conn, _status),
    do: Problem.respond(conn, :invalid_params, %{role: "Choose member or organization_admin."})

  defp respond({:error, reason}, conn, _status), do: Problem.respond(conn, reason)
end
