defmodule Cadence.Accounts.MembershipAdministration do
  @moduledoc """
  Organization membership and invitation writes for people administration (console People):
  change a member's role, remove a member, revoke a pending invitation.

  An organization always keeps at least one active `organization_admin`: demoting or removing
  the last one is refused (`:last_admin`), checked under a lock on the organization's admin
  memberships so two concurrent demotions can't both pass. Removal revokes the membership
  (`lifecycle_state: "revoked"`) rather than deleting it, so history keeps pointing at it; the
  person loses access on their next request because scopes are built from active memberships.
  Callers authorize (`Cadence.Administration.PeopleAdministration`).
  """

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationInvitationRow, OrganizationMembershipRow}
  alias Cadence.Repo

  @roles %{"organization_admin" => "organization_admin", "member" => "member"}

  @spec change_role(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, :member_not_found | :last_admin | :invalid_role}
  def change_role(organization_id, user_id, role) do
    with {:ok, role} <- role(role) do
      Repo.transaction(fn -> locked_change(organization_id, user_id, %{role: role}, role) end)
    end
  end

  @spec remove_member(binary(), binary()) ::
          {:ok, map()} | {:error, :member_not_found | :last_admin}
  def remove_member(organization_id, user_id) do
    Repo.transaction(fn ->
      locked_change(organization_id, user_id, %{lifecycle_state: "revoked"}, nil)
    end)
  end

  # `new_role` nil means the member is being removed.
  defp locked_change(organization_id, user_id, attrs, new_role) do
    with {:ok, row} <- lock_member(organization_id, user_id),
         :ok <- keeps_an_admin(organization_id, row, new_role),
         {:ok, updated} <- write(row, attrs) do
      view(updated)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "A pending invitation (for resend), or `:invitation_not_found`."
  @spec fetch_pending_invitation(binary(), binary()) ::
          {:ok, struct()} | {:error, :invitation_not_found}
  def fetch_pending_invitation(organization_id, invitation_id) do
    case Repo.get_by(OrganizationInvitationRow,
           organization_invitation_id: invitation_id,
           organization_id: organization_id,
           status: "pending"
         ) do
      nil -> {:error, :invitation_not_found}
      row -> {:ok, row}
    end
  end

  @spec revoke_invitation(binary(), binary()) :: :ok | {:error, :invitation_not_found}
  def revoke_invitation(organization_id, invitation_id) do
    {count, _rows} =
      OrganizationInvitationRow
      |> where(
        [i],
        i.organization_invitation_id == ^invitation_id and i.organization_id == ^organization_id and
          i.status == "pending"
      )
      |> Repo.update_all(set: [status: "revoked", updated_at: DateTime.utc_now()])

    if count == 1, do: :ok, else: {:error, :invitation_not_found}
  end

  defp role(role) do
    case Map.fetch(@roles, to_string(role)) do
      {:ok, role} -> {:ok, role}
      :error -> {:error, :invalid_role}
    end
  end

  defp lock_member(organization_id, user_id) do
    OrganizationMembershipRow
    |> where(
      [m],
      m.organization_id == ^organization_id and m.user_id == ^user_id and
        m.lifecycle_state == "active"
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :member_not_found}
      row -> {:ok, row}
    end
  end

  defp keeps_an_admin(_organization_id, %{role: role}, role), do: :ok

  defp keeps_an_admin(organization_id, %{role: "organization_admin"} = row, _new_role) do
    others =
      OrganizationMembershipRow
      |> where(
        [m],
        m.organization_id == ^organization_id and m.lifecycle_state == "active" and
          m.role == "organization_admin" and m.user_id != ^row.user_id
      )
      |> lock("FOR UPDATE")
      |> Repo.all()

    if others == [], do: {:error, :last_admin}, else: :ok
  end

  defp keeps_an_admin(_organization_id, _row, _new_role), do: :ok

  defp write(row, attrs),
    do:
      row
      |> OrganizationMembershipRow.update_changeset(Map.merge(%{metadata: row.metadata}, attrs))
      |> Repo.update()

  defp view(row),
    do: %{
      user_id: row.user_id,
      role: String.to_existing_atom(row.role),
      state: String.to_existing_atom(row.lifecycle_state)
    }
end
