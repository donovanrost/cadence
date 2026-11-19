defmodule CadenceWeb.Console.ServiceIdentityController do
  @moduledoc """
  Service identity writes (O6) under `/api/console/v1/organizations/:organization_id`: create,
  rotate, revoke. Create and rotate return the API token once. Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.ServiceIdentityAdministration, as: Identities
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def create(conn, %{"organization_id" => organization_id} = params) do
    conn.assigns.current_scope
    |> Identities.create(organization_id, params)
    |> respond(conn, :created)
  end

  def rotate(conn, %{"organization_id" => organization_id, "service_identity_id" => id}) do
    conn.assigns.current_scope
    |> Identities.rotate(organization_id, id)
    |> respond(conn, :ok)
  end

  def revoke(conn, %{"organization_id" => organization_id, "service_identity_id" => id}) do
    case Identities.revoke(conn.assigns.current_scope, organization_id, id) do
      :ok -> send_resp(conn, :no_content, "")
      error -> respond(error, conn, :ok)
    end
  end

  # The token is in the body once; tell caches and proxies not to keep it.
  defp respond({:ok, data}, conn, status) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{data: ConfigJSON.encode(data)})
  end

  defp respond({:error, {:invalid, details}}, conn, _status),
    do: Problem.respond(conn, :invalid_params, details)

  defp respond({:error, reason}, conn, _status) when is_atom(reason),
    do: Problem.respond(conn, reason)

  defp respond({:error, _reason}, conn, _status), do: Problem.respond(conn, :invalid_params)
end
