defmodule Cadence.Reads.OrganizationAudit.AccountEvents do
  @moduledoc """
  Members' changes to their own sign-in for the organization audit (`kind: "account"`):
  password changed, a session signed out, every other session signed out. From
  `Accounts.AccountEvents`, for the organization's current and former members (a person in
  two organizations shows in both). The actor is the member; there is no target. No secrets:
  the action says only what changed.
  """

  alias Cadence.Accounts.AccountEvents
  alias Cadence.Accounts.MembershipAdministration

  @limit 500

  @spec list(binary()) :: [map()]
  def list(organization_id) do
    %{memberships: memberships} = MembershipAdministration.access_history(organization_id)

    memberships
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()
    |> AccountEvents.list(@limit)
    |> Enum.map(&event/1)
  end

  defp event(entry) do
    %{
      id: "account:#{entry.id}",
      at: entry.at,
      actor: %{kind: "user", id: entry.actor_id, name: nil},
      kind: "account",
      action: action(entry.action, entry.details),
      target: nil,
      mission: nil,
      reason: nil
    }
  end

  defp action("password_changed", %{"other_sessions_signed_out" => n}) when n > 0,
    do: "Changed their password and signed out #{sessions(n)}"

  defp action("password_changed", _details), do: "Changed their password"

  defp action("session_signed_out", %{"current" => true}),
    do: "Signed out of the session they were using"

  defp action("session_signed_out", _details), do: "Signed out one of their other sessions"

  defp action("other_sessions_signed_out", %{"count" => n}),
    do: "Signed out #{sessions(n)}"

  defp action(other, _details), do: other

  defp sessions(1), do: "1 other session"
  defp sessions(n), do: "#{n} other sessions"
end
