defmodule Cadence.Accounts.InvitationResponses do
  @moduledoc """
  A signed-in user's own invitations (§11 L21): the pending ones addressed to their current
  email, and declining one by id. Accepting by id is `Accounts.accept_invitation_as_user/2`.
  The token path (L5, signed in or out) resolves its token to an id and calls the same functions.

  Pending uses the same predicate as `Accounts.count_pending_invitations_for_user/1`: status
  pending, not expired, the email of an active user.
  """

  import Ecto.Query

  alias Cadence.Accounts
  alias Cadence.Accounts.{OrganizationInvitationRow, UserRow}
  alias Cadence.Organizations.OrganizationRow
  alias Cadence.Repo

  @type pending :: %{
          organization_invitation_id: binary(),
          organization: %{id: binary(), slug: binary(), name: binary()},
          membership_role: binary(),
          invited_by: %{name: binary() | nil} | nil,
          invited_at: DateTime.t(),
          expires_at: DateTime.t()
        }

  @doc "Pending, unexpired invitations for the user's current email, oldest first."
  @spec list_pending_invitations_for_user(binary()) :: [pending()]
  def list_pending_invitations_for_user(user_id) when is_binary(user_id) do
    now = DateTime.utc_now()

    OrganizationInvitationRow
    |> join(:inner, [i], u in UserRow, on: u.email == i.email)
    |> join(:inner, [i], o in OrganizationRow, on: o.organization_id == i.organization_id)
    |> join(:left, [i], inviter in UserRow, on: inviter.user_id == i.invited_by_user_id)
    |> where(
      [i, u],
      u.user_id == ^user_id and u.lifecycle_state == "active" and i.status == "pending" and
        i.expires_at > ^now
    )
    |> order_by([i], asc: i.inserted_at, asc: i.organization_invitation_id)
    |> select([i, _u, o, inviter], %{
      organization_invitation_id: i.organization_invitation_id,
      organization: %{id: o.organization_id, slug: o.slug, name: o.display_name},
      membership_role: i.membership_role,
      inviter_id: inviter.user_id,
      inviter_name: coalesce(inviter.display_name, inviter.email),
      invited_at: i.inserted_at,
      expires_at: i.expires_at
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      row
      |> Map.put(:invited_by, row.inviter_id && %{name: row.inviter_name})
      |> Map.drop([:inviter_id, :inviter_name])
      |> Map.update!(:invited_at, &to_utc/1)
    end)
  end

  @doc """
  Declines a pending invitation addressed to the user. Final: the status becomes `declined`,
  recorded with who and when (`metadata.declined_by_user_id`, `declined_at`).
  """
  @spec decline_invitation_as_user(binary(), binary()) ::
          {:ok, Cadence.Accounts.OrganizationInvitation.t()}
          | {:error,
             :user_not_found
             | :invitation_not_found
             | :invitation_not_pending
             | :invitation_expired
             | :email_mismatch
             | term()}
  def decline_invitation_as_user(user_id, invitation_id)
      when is_binary(user_id) and is_binary(invitation_id) do
    Repo.transaction(fn ->
      with {:ok, user} <- Accounts.fetch_user(user_id),
           {:ok, row, invitation} <- Accounts.lock_pending_invitation(Repo, invitation_id),
           true <- Accounts.invitation_for_user?(user, invitation) || {:error, :email_mismatch},
           {:ok, declined} <- mark_declined(row, user.user_id) do
        declined
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp mark_declined(row, user_id) do
    metadata =
      Map.merge(row.metadata || %{}, %{
        "declined_by_user_id" => user_id,
        "declined_at" => DateTime.to_iso8601(DateTime.utc_now())
      })

    row
    |> OrganizationInvitationRow.update_changeset(%{
      status: "declined",
      membership_role: row.membership_role,
      grant_platform_admin: row.grant_platform_admin,
      expires_at: row.expires_at,
      metadata: metadata
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, OrganizationInvitationRow.to_domain(updated)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_utc(at), do: at
end
