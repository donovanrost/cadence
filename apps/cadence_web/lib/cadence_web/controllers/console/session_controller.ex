defmodule CadenceWeb.Console.SessionController do
  @moduledoc """
  Console bootstrap (`GET /api/v1/session`), sign-out (`DELETE /api/v1/session`),
  default-organization selection (`PUT /api/v1/session/organization`) and admin mode (L6:
  `POST` / `DELETE /api/v1/session/admin-mode`). Contract: docs/apogee/api/session.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Administration.ConsoleAdmin
  alias Cadence.Auth.Scope
  alias CadenceWeb.AdminMode
  alias CadenceWeb.Console.Access
  alias CadenceWeb.Console.Capabilities
  alias CadenceWeb.Console.Problem
  alias CadenceWeb.Console.SessionJSON
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.Endpoint

  def show(conn, _params) do
    render_session(conn, conn.assigns.current_scope)
  end

  @doc """
  Signs this browser out (#664): revokes the session token, then disconnects that session's live
  sockets, then drops and renews the cookie session. Revoking first means a socket that reconnects
  straight away is refused. A person only: service identities aren't in `ServiceAccess`.
  """
  def delete(conn, _params) do
    session_token = conn.assigns.console_credentials.session_token
    :ok = Cadence.Auth.revoke_user_session(session_token)
    Endpoint.broadcast(ConsoleSocket.id_for_session_token(session_token), "disconnect", %{})

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> send_resp(:no_content, "")
  end

  def update_organization(conn, %{"organization_id" => organization_id})
      when is_binary(organization_id) do
    scope = conn.assigns.current_scope

    with :ok <- authorize_selection(scope, organization_id),
         credentials = %{
           conn.assigns.console_credentials
           | current_organization_id: organization_id
         },
         {:ok, rescoped} <- Access.authenticate(credentials) do
      conn
      |> put_session(:current_organization_id, organization_id)
      |> render_session(rescoped)
    else
      {:error, reason} -> Problem.respond(conn, reason)
    end
  end

  # The shell resolves URL org slugs; a platform admin in admin mode can open
  # any organization this way (qa #15), others only their memberships.
  def update_organization(conn, %{"organization_slug" => slug}) when is_binary(slug) do
    case Cadence.Organizations.fetch_organization_by_slug(slug) do
      {:ok, organization} ->
        update_organization(conn, %{"organization_id" => organization.organization_id})

      {:error, _not_found} ->
        Problem.respond(conn, :organization_not_found)
    end
  end

  def update_organization(conn, _params) do
    Problem.respond(conn, :invalid_params, %{
      organization_id: "is required (or organization_slug)"
    })
  end

  @doc """
  Enters admin mode for an eligible platform admin: the password is checked through the attempt
  limit like sign-in, and admin mode lasts `AdminMode.expires_at/0` (1 h). Entering while on
  starts a fresh hour.
  """
  def enter_admin_mode(conn, %{"password" => password}) when is_binary(password) do
    scope = conn.assigns.current_scope

    with true <- Scope.platform_admin_eligible?(scope),
         :ok <- Cadence.Auth.verify_user_password(scope.user, password, ip: conn.remote_ip) do
      expires_at = AdminMode.expires_at()
      ConsoleAdmin.record_admin_mode(scope.user.user_id, :entered, iso(expires_at))

      conn
      |> put_session(:admin_mode_expires_at, expires_at)
      |> json(%{data: %{expires_at: iso(expires_at)}})
    else
      false ->
        Problem.respond(conn, :forbidden)

      {:error, :invalid_credentials} ->
        Problem.respond(conn, :password_incorrect)

      {:error, {:too_many_attempts, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> Problem.respond(:too_many_attempts, %{retry_after: retry_after})
    end
  end

  def enter_admin_mode(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{password: "is required"})

  @doc "Leaves admin mode (idempotent)."
  def leave_admin_mode(conn, _params) do
    if is_integer(get_session(conn, :admin_mode_expires_at)),
      do: ConsoleAdmin.record_admin_mode(conn.assigns.current_scope.user.user_id, :left, nil)

    conn
    |> delete_session(:admin_mode_expires_at)
    |> send_resp(:no_content, "")
  end

  defp render_session(conn, %Scope{} = scope) do
    session =
      SessionJSON.session(%{
        scope: scope,
        organizations: organizations(scope),
        csrf_token: get_csrf_token(),
        admin_mode_expires_at: admin_mode_expires_at(conn)
      })

    # L21: the org switcher footer and /no-organization show it on every page.
    json(conn, %{data: Map.put(session, :pending_invitations_count, pending_invitations(scope))})
  end

  defp pending_invitations(%Scope{user: user}),
    do: Cadence.Accounts.count_pending_invitations_for_user(user.user_id)

  # Memberships, plus the current organization when a platform admin in admin
  # mode is viewing one they are not a member of. Capabilities are computed per
  # organization with the same Scope rules the server enforces there.
  defp organizations(%Scope{user: user} = scope) do
    memberships =
      Enum.map(Cadence.Accounts.list_user_memberships(user.user_id), fn entry ->
        {entry.organization, entry.membership}
      end)

    entries =
      case scope.organization do
        nil ->
          memberships

        organization ->
          if Enum.any?(memberships, fn {org, _membership} ->
               org.organization_id == organization.organization_id
             end),
             do: memberships,
             else: memberships ++ [{organization, nil}]
      end

    Enum.map(entries, fn {organization, membership} ->
      org_scope =
        Scope.new(%{
          user: user,
          organization_id: organization.organization_id,
          organization: organization,
          organization_membership: membership,
          admin_mode?: scope.admin_mode?
        })

      %{
        organization: organization,
        role: membership && membership.role,
        capabilities: Capabilities.organization(org_scope),
        missions: Cadence.Missions.list_missions(organization.organization_id)
      }
    end)
  end

  defp authorize_selection(%Scope{} = scope, organization_id) do
    result =
      if Scope.admin_mode?(scope) do
        Cadence.Organizations.fetch_organization(organization_id)
      else
        Cadence.Accounts.fetch_user_membership(scope.user.user_id, organization_id)
      end

    case result do
      {:ok, _found} -> :ok
      {:error, _reason} -> {:error, :organization_not_found}
    end
  end

  defp admin_mode_expires_at(conn) do
    case get_session(conn, :admin_mode_expires_at) do
      expires_at when is_integer(expires_at) -> iso(expires_at)
      _none -> nil
    end
  end

  defp iso(unix_seconds), do: unix_seconds |> DateTime.from_unix!() |> DateTime.to_iso8601()
end
