defmodule CadenceWeb.Console.SessionController do
  @moduledoc """
  Console bootstrap (`GET /api/console/v1/session`) and default-organization
  selection (`PUT /api/console/v1/session/organization`).
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Scope
  alias CadenceWeb.Console.Access
  alias CadenceWeb.Console.Capabilities
  alias CadenceWeb.Console.Problem
  alias CadenceWeb.Console.SessionJSON

  def show(conn, _params) do
    render_session(conn, conn.assigns.current_scope)
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

  defp render_session(conn, %Scope{} = scope) do
    json(conn, %{
      data:
        SessionJSON.session(%{
          scope: scope,
          organizations: organizations(scope),
          csrf_token: get_csrf_token()
        })
    })
  end

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
end
