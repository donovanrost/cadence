defmodule CadenceWeb.Console.AdminController do
  @moduledoc """
  The console admin area (L7, `/api/console/v1/admin`), platform administrators in admin mode
  only: `403 admin_mode_required` otherwise (admin mode lapsed, or the capability is gone).
  Writes are recorded in the platform audit. Contract: docs/apogee/api/admin.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.{
    ConsoleAdmin,
    ConsoleOrganizations,
    ConsoleServiceIdentities,
    PlatformAudit
  }

  alias Cadence.Reads.Administration.ConsoleRuntime

  alias CadenceWeb.Console.{ConfigJSON, Problem}

  # AD1
  def organizations(conn, params),
    do: respond(conn, ConsoleOrganizations.list(scope(conn), Map.take(params, ~w(q after))))

  def slug(conn, %{"slug" => slug}) when is_binary(slug),
    do: respond(conn, ConsoleOrganizations.slug(scope(conn), slug))

  def slug(conn, _params), do: Problem.respond(conn, :invalid_params, %{slug: "is required"})

  def create_organization(conn, params) do
    input = Map.take(params, ~w(name slug first_admin_email))
    respond(conn, ConsoleAdmin.create_organization(scope(conn), input), :created)
  end

  # AD2
  def organization(conn, %{"id" => id}),
    do: respond(conn, ConsoleOrganizations.show(scope(conn), id))

  def invite(conn, %{"id" => id} = params) do
    input = Map.take(params, ~w(email role))
    respond(conn, ConsoleAdmin.invite_member(scope(conn), id, input), :created)
  end

  def withdraw(conn, %{"id" => id, "invitation_id" => invitation_id}),
    do: respond(conn, ConsoleAdmin.withdraw_invitation(scope(conn), id, invitation_id))

  # AD3
  def service_identities(conn, params),
    do:
      respond(
        conn,
        ConsoleServiceIdentities.list(scope(conn), Map.take(params, ~w(organization_id)))
      )

  def issue(conn, params) do
    input = Map.take(params, ~w(organization_id name capability mission_id))
    result = ConsoleAdmin.issue_service_identity(scope(conn), input)

    respond(
      no_store(conn),
      ConsoleServiceIdentities.issued(result, params["organization_id"]),
      :created
    )
  end

  def rotate(conn, %{"id" => id, "organization_id" => org}) do
    result = ConsoleAdmin.rotate_service_identity(scope(conn), org, id)
    respond(no_store(conn), ConsoleServiceIdentities.issued(result, org))
  end

  def rotate(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{organization_id: "is required"})

  def revoke(conn, %{"id" => id, "organization_id" => org}),
    do: respond(conn, ConsoleAdmin.revoke_service_identity(scope(conn), org, id))

  def revoke(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{organization_id: "is required"})

  # AD4 and the platform audit
  def runtime(conn, _params), do: respond(conn, ConsoleRuntime.load(scope(conn)))

  def audit(conn, params),
    do: respond(conn, PlatformAudit.list(scope(conn), Map.take(params, ~w(after))))

  defp respond(conn, result, status \\ :ok)

  defp respond(conn, {:ok, data}, status),
    do: conn |> put_status(status) |> json(%{data: ConfigJSON.encode(data)})

  defp respond(conn, {:error, :unavailable}, _status),
    do: Problem.respond(conn, :admin_mode_required)

  defp respond(conn, {:invalid, details}, _status),
    do: Problem.respond(conn, :invalid_params, details)

  defp respond(conn, {:error, {:invalid, details}}, _status),
    do: Problem.respond(conn, :invalid_params, details)

  defp respond(conn, {:error, reason}, _status)
       when reason in [:organization_not_found, :not_found],
       do: Problem.respond(conn, :organization_not_found)

  defp respond(conn, {:error, :invitation_not_found}, _status),
    do: Problem.respond(conn, :invitation_not_found)

  defp respond(conn, {:error, reason}, _status)
       when reason in [:service_identity_not_found, :forbidden, :scope_mismatch],
       do: Problem.respond(conn, :not_found)

  defp respond(conn, {:error, _reason}, _status), do: Problem.respond(conn, :invalid_params)

  # The token is in the body once; tell caches and proxies not to keep it (as People's O6 does).
  defp no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")

  defp scope(conn), do: conn.assigns.current_scope
end
