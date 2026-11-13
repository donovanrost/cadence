defmodule CadenceWeb.Console.AccountInvitationController do
  @moduledoc """
  The signed-in user's own pending invitations (§11 L21; contract session.md §My invitations):
  list, accept and decline by id. People who aren't signed in use `/invitations/:token`.

  An invitation that doesn't exist or isn't addressed to the caller's email is `404`, the same
  answer either way, so ids don't leak. One that was answered already, revoked or expired is
  `409 invitation_not_pending` with `details.status`.
  """

  use CadenceWeb, :controller

  alias Cadence.Accounts
  alias Cadence.Organizations
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, _params) do
    invitations =
      conn
      |> user()
      |> Map.fetch!(:user_id)
      |> Accounts.list_pending_invitations_for_user()
      |> Enum.map(&row/1)

    json(conn, %{data: ConfigJSON.encode(%{invitations: invitations})})
  end

  def accept(conn, %{"invitation_id" => id}) do
    with {:ok, %{membership: membership, invitation: invitation}} <-
           Accounts.accept_invitation_as_user(user(conn).user_id, id),
         {:ok, organization} <- Organizations.fetch_organization(invitation.organization_id) do
      json(conn, %{
        data:
          ConfigJSON.encode(%{
            organization: %{
              id: organization.organization_id,
              slug: organization.slug,
              name: organization.display_name
            },
            role: membership.role
          })
      })
    else
      {:error, reason} -> error(conn, id, reason)
    end
  end

  def decline(conn, %{"invitation_id" => id}) do
    case Accounts.decline_invitation_as_user(user(conn).user_id, id) do
      {:ok, invitation} ->
        json(conn, %{data: %{id: invitation.organization_invitation_id, status: "declined"}})

      {:error, reason} ->
        error(conn, id, reason)
    end
  end

  defp row(invitation) do
    %{
      id: invitation.organization_invitation_id,
      organization: invitation.organization,
      role: invitation.membership_role,
      invited_by: invitation.invited_by,
      invited_at: invitation.invited_at,
      expires_at: invitation.expires_at
    }
  end

  defp error(conn, id, reason) when reason in [:invitation_not_pending, :invitation_expired] do
    case status(user(conn), id) do
      nil -> Problem.respond(conn, :invitation_not_found)
      status -> Problem.respond(conn, :invitation_not_pending, %{status: status})
    end
  end

  defp error(conn, _id, _not_found_or_not_mine), do: Problem.respond(conn, :invitation_not_found)

  # Only for an invitation addressed to this user (or one they accepted), so nothing leaks.
  defp status(user, id) do
    case Accounts.invitation_statuses_for_user(user, [id]) do
      %{^id => %{status: "pending"}} -> "expired"
      %{^id => %{status: status}} -> status
      _not_mine -> nil
    end
  end

  defp user(conn), do: conn.assigns.current_scope.user
end
