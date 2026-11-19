defmodule CadenceWeb.Console.ServiceIdentityController do
  @moduledoc """
  Service identity writes (O6) under `/api/console/v1/organizations/:organization_id`: create,
  rotate, revoke, and recording who is accountable (#280). Create and rotate return the API token once. Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.ServiceIdentityAdministration, as: Identities
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def create(conn, %{"organization_id" => organization_id} = params) do
    conn.assigns.current_scope
    |> Identities.create(organization_id, params)
    |> beyond_issuer(:create)
    |> respond(conn, :created)
  end

  def rotate(conn, %{"organization_id" => organization_id, "service_identity_id" => id}) do
    conn.assigns.current_scope
    |> Identities.rotate(organization_id, id)
    |> beyond_issuer(:rotate)
    |> respond(conn, :ok)
  end

  # #280: record who is accountable for an identity (the acting admin joins them). 204 on success.
  def accountable(
        conn,
        %{"organization_id" => organization_id, "service_identity_id" => id} = params
      ) do
    case Identities.record_accountable(conn.assigns.current_scope, organization_id, id, params) do
      :ok -> send_resp(conn, :no_content, "")
      error -> respond(error, conn, :ok)
    end
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

  defp respond({:beyond_issuer, message, capabilities}, conn, _status) do
    conn
    |> put_status(:forbidden)
    |> json(
      Problem.body("capability_beyond_issuer", message, %{
        capabilities: Enum.map(capabilities, &Atom.to_string/1)
      })
    )
  end

  defp respond({:error, {:invalid, details}}, conn, _status),
    do: Problem.respond(conn, :invalid_params, details)

  defp respond({:error, reason}, conn, _status) when is_atom(reason),
    do: Problem.respond(conn, reason)

  defp respond({:error, _reason}, conn, _status), do: Problem.respond(conn, :invalid_params)

  # ux U104 (#281). Unreachable while only organization admins issue, who hold every capability a
  # service identity can get; it answers if issuance ever widens.
  defp beyond_issuer({:error, {:capability_beyond_issuer, missing}}, act),
    do: {:beyond_issuer, beyond_issuer_message(act, roles(missing)), missing}

  defp beyond_issuer(result, _act), do: result

  defp beyond_issuer_message(:create, roles),
    do:
      "Not created: you can't give a service identity access you don't have yourself (#{roles}). " <>
        "Leave it out, or ask someone who has it to create the service identity."

  defp beyond_issuer_message(:rotate, roles),
    do:
      "Not rotated: this service identity has access you don't have yourself (#{roles}), " <>
        "so you can't rotate its key. Ask someone who has that access to rotate it."

  @role_words %{
    platform_admin: "Platform admin",
    organization_admin: "Org admin",
    mission_admin: "Mission admin"
  }

  defp roles(capabilities) do
    words = Enum.map(capabilities, &Map.get(@role_words, &1, Atom.to_string(&1)))

    case Enum.split(words, 3) do
      {shown, []} -> Enum.join(shown, ", ")
      {shown, rest} -> Enum.join(shown, ", ") <> " and #{length(rest)} more"
    end
  end
end
