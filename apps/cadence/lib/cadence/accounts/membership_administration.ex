defmodule Cadence.Accounts.MembershipAdministration do
  @moduledoc """
  Organization membership and invitation writes for people administration (console People):
  change a member's role, remove a member, revoke a pending invitation; plus the access history
  the organization audit reads.

  An organization always keeps at least one active `organization_admin`: demoting or removing
  the last one is refused (`:last_admin`), checked under a lock on the organization's admin
  memberships so two concurrent demotions can't both pass. Removal revokes the membership
  (`lifecycle_state: "revoked"`) rather than deleting it, so history keeps pointing at it; the
  person loses access on their next request because scopes are built from active memberships.

  Each write records who made it and when in the row's metadata (`"audit"` on memberships,
  `"revoked_by"` / `"revoked_at"` on invitations), which `access_history/1` returns.
  Callers authorize (`Cadence.Administration.OrganizationPeople`).
  """

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationInvitationRow, OrganizationMembershipRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @roles %{"organization_admin" => "organization_admin", "member" => "member"}
  @max_audit 50

  @spec change_role(binary(), binary(), binary() | atom(), binary() | nil) ::
          {:ok, map()} | {:error, :member_not_found | :last_admin | :invalid_role}
  def change_role(organization_id, user_id, role, actor_id) do
    with {:ok, role} <- role(role) do
      Repo.transaction(fn ->
        locked_change(organization_id, user_id, role, actor_id, &role_change(&1, role))
      end)
    end
  end

  defp role_change(row, role),
    do: {%{role: role}, %{"action" => "role_changed", "from" => row.role, "to" => role}}

  @spec remove_member(binary(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, :member_not_found | :last_admin}
  def remove_member(organization_id, user_id, actor_id) do
    Repo.transaction(fn ->
      locked_change(organization_id, user_id, nil, actor_id, fn row ->
        {%{lifecycle_state: "revoked"}, %{"action" => "removed", "role" => row.role}}
      end)
    end)
  end

  # `new_role` nil means the member is being removed.
  defp locked_change(organization_id, user_id, new_role, actor_id, change) do
    with {:ok, row} <- lock_member(organization_id, user_id),
         :ok <- keeps_an_admin(organization_id, row, new_role),
         {attrs, event} = change.(row),
         {:ok, updated} <- write(row, attrs, event, actor_id) do
      view(updated)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "A pending invitation (for resend), or `:invitation_not_found`."
  @spec fetch_pending_invitation(binary(), binary()) ::
          {:ok, struct()} | {:error, :invitation_not_found}
  def fetch_pending_invitation(organization_id, invitation_id) do
    case pending_invitation(organization_id, invitation_id) do
      nil -> {:error, :invitation_not_found}
      row -> {:ok, row}
    end
  end

  @spec revoke_invitation(binary(), binary(), binary() | nil) ::
          :ok | {:error, :invitation_not_found}
  def revoke_invitation(organization_id, invitation_id, actor_id) do
    with %OrganizationInvitationRow{} = row <- pending_invitation(organization_id, invitation_id),
         metadata =
           (JsonDocument.unwrap_value(row.metadata) || %{})
           |> Map.merge(%{"revoked_by" => actor_id, "revoked_at" => now()}),
         {:ok, _row} <-
           row
           |> OrganizationInvitationRow.update_changeset(%{
             status: "revoked",
             metadata: JsonDocument.wrap_value(metadata)
           })
           |> Repo.update() do
      :ok
    else
      _missing -> {:error, :invitation_not_found}
    end
  end

  @doc """
  The organization's access history for the audit: every invitation (sent, accepted, revoked)
  and every membership (when it began, and the role changes and removal recorded on it).
  """
  @spec access_history(binary()) :: %{invitations: [map()], memberships: [map()]}
  def access_history(organization_id) do
    invitations =
      OrganizationInvitationRow
      |> where([i], i.organization_id == ^organization_id)
      |> Repo.all()
      |> Enum.map(&invitation_history/1)

    memberships =
      OrganizationMembershipRow
      |> where([m], m.organization_id == ^organization_id)
      |> Repo.all()
      |> Enum.map(&membership_history/1)

    %{invitations: invitations, memberships: memberships}
  end

  defp invitation_history(row) do
    metadata = JsonDocument.unwrap_value(row.metadata) || %{}

    %{
      id: row.organization_invitation_id,
      email: row.email,
      role: row.membership_role,
      status: row.status,
      invited_by: row.invited_by_user_id,
      sent_at: row.inserted_at,
      accepted_by: row.accepted_by_user_id,
      accepted_at: row.accepted_at,
      revoked_by: metadata["revoked_by"],
      revoked_at: parse(metadata["revoked_at"])
    }
  end

  defp membership_history(row) do
    metadata = JsonDocument.unwrap_value(row.metadata) || %{}

    %{
      user_id: row.user_id,
      role: row.role,
      state: row.lifecycle_state,
      began_at: row.inserted_at,
      events:
        metadata
        |> Map.get("audit")
        |> List.wrap()
        |> Enum.map(&Map.update(&1, "at", nil, fn at -> parse(at) end))
    }
  end

  defp pending_invitation(organization_id, invitation_id),
    do:
      Repo.get_by(OrganizationInvitationRow,
        organization_invitation_id: invitation_id,
        organization_id: organization_id,
        status: "pending"
      )

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

  defp write(row, attrs, event, actor_id) do
    metadata = JsonDocument.unwrap_value(row.metadata) || %{}
    event = Map.merge(event, %{"by" => actor_id, "at" => now()})

    audit =
      metadata |> Map.get("audit") |> List.wrap() |> Kernel.++([event]) |> Enum.take(-@max_audit)

    row
    |> OrganizationMembershipRow.update_changeset(
      Map.merge(%{metadata: JsonDocument.wrap_value(Map.put(metadata, "audit", audit))}, attrs)
    )
    |> Repo.update()
  end

  defp view(row),
    do: %{
      user_id: row.user_id,
      role: String.to_existing_atom(row.role),
      state: String.to_existing_atom(row.lifecycle_state)
    }

  defp now, do: DateTime.to_iso8601(DateTime.utc_now())

  defp parse(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp parse(_none), do: nil
end
