defmodule CadenceWeb.Console.ServiceIdentityController do
  @moduledoc """
  Service identity writes (O6) under `/api/v1/organizations/:organization_id`: create,
  rotate, revoke, and recording who is accountable (#280). Create and rotate return the API token once. Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.ServiceIdentityAdministration, as: Identities
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def create(conn, %{"organization_id" => organization_id} = params) do
    conn.assigns.current_scope
    |> Identities.create(organization_id, params)
    |> refusal(:create)
    |> respond(conn, :created)
  end

  def rotate(conn, %{"organization_id" => organization_id, "service_identity_id" => id}) do
    conn.assigns.current_scope
    |> Identities.rotate(organization_id, id)
    |> refusal(:rotate)
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
      error -> error |> refusal(:revoke) |> respond(conn, :ok)
    end
  end

  # The token is in the body once; tell caches and proxies not to keep it.
  defp respond({:ok, data}, conn, status) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{data: ConfigJSON.encode(data)})
  end

  defp respond({:refused, code, message, details}, conn, _status),
    do: conn |> put_status(:forbidden) |> json(Problem.body(code, message, details))

  defp respond({:error, {:invalid, details}}, conn, _status),
    do: Problem.respond(conn, :invalid_params, details)

  defp respond({:error, reason}, conn, _status) when is_atom(reason),
    do: Problem.respond(conn, reason)

  defp respond({:error, _reason}, conn, _status), do: Problem.respond(conn, :invalid_params)

  # ux U104 (#281). Both unreachable today: the organization scope refuses a service identity
  # before this controller, and an organization admin holds every capability a service can get.
  defp refusal({:error, :authenticated_user_required}, act),
    do: {:refused, "authenticated_user_required", person_only_message(act), nil}

  defp refusal({:error, {:capability_beyond_issuer, missing}}, act),
    do:
      {:refused, "capability_beyond_issuer", beyond_issuer_message(act, roles(missing)),
       %{capabilities: Enum.map(missing, &Atom.to_string/1)}}

  defp refusal(result, _act), do: result

  defp person_only_message(:create),
    do:
      "Not created: only a person can create a service identity, not another service identity. " <>
        "An org admin creates it in People › Service identities."

  defp person_only_message(:rotate),
    do:
      "Not rotated: only a person can rotate a service identity's key, not a service identity. " <>
        "An org admin rotates it in People › Service identities."

  defp person_only_message(:revoke),
    do:
      "Not revoked: only a person can revoke a service identity, not a service identity. " <>
        "An org admin revokes it in People › Service identities."

  defp beyond_issuer_message(:create, roles),
    do:
      "Not created: you can't give a service identity access you don't have yourself (#{roles}). " <>
        "Leave it out, or ask someone who has it to create the service identity."

  defp beyond_issuer_message(:rotate, roles),
    do:
      "Not rotated: this service identity has access you don't have yourself (#{roles}), " <>
        "so you can't rotate its key. Ask someone who has that access to rotate it."

  @role_words %{organization_admin: "Org admin", mission_admin: "Mission admin"}

  defp roles(capabilities) do
    words = Enum.map(capabilities, &Map.get(@role_words, &1, Atom.to_string(&1)))

    case Enum.split(words, 3) do
      {shown, []} -> Enum.join(shown, ", ")
      {shown, rest} -> Enum.join(shown, ", ") <> " and #{length(rest)} more"
    end
  end
end
