defmodule Cadence.Accounts.InvitationTokens do
  @moduledoc """
  What an emailed invitation token refers to (console L5), whatever its state, for the page the
  link opens. Only a valid token says anything: an unknown one is `{:error, :not_found}` with no
  detail, and whether the invited email has an account is told only to the token's holder (the
  person the link was emailed to), never by an email lookup.

  `state`: `:open` (pending, not expired), `:expired`, `:withdrawn` (revoked by an admin),
  `:used` (accepted) or `:declined`.
  """

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationInvitationRow, Token, UserRow}
  alias Cadence.Organizations.OrganizationRow
  alias Cadence.Repo

  @type view :: %{
          invitation_id: binary(),
          state: :open | :expired | :withdrawn | :used | :declined,
          email: binary(),
          organization: %{id: binary(), slug: binary(), name: binary()},
          membership_role: binary(),
          invited_by: %{name: binary() | nil} | nil,
          invited_at: DateTime.t(),
          expires_at: DateTime.t(),
          account?: boolean()
        }

  @spec inspect_token(binary()) :: {:ok, view()} | {:error, :not_found}
  def inspect_token(token) when is_binary(token) and byte_size(token) in 1..512 do
    OrganizationInvitationRow
    |> where([i], i.token_digest == ^Token.digest(token))
    |> join(:inner, [i], o in OrganizationRow, on: o.organization_id == i.organization_id)
    |> join(:left, [i], inviter in UserRow, on: inviter.user_id == i.invited_by_user_id)
    |> select([i, o, inviter], %{
      row: i,
      organization: %{id: o.organization_id, slug: o.slug, name: o.display_name},
      inviter_id: inviter.user_id,
      inviter_name: coalesce(inviter.display_name, inviter.email)
    })
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      found -> {:ok, view(found)}
    end
  end

  def inspect_token(_token), do: {:error, :not_found}

  defp view(%{row: row} = found) do
    %{
      invitation_id: row.organization_invitation_id,
      state: state(row.status, row.expires_at),
      email: row.email,
      organization: found.organization,
      membership_role: row.membership_role,
      invited_by: found.inviter_id && %{name: found.inviter_name},
      invited_at: to_utc(row.inserted_at),
      expires_at: row.expires_at,
      account?: Repo.exists?(where(UserRow, [u], u.email == ^row.email))
    }
  end

  defp state("pending", expires_at),
    do: if(DateTime.before?(DateTime.utc_now(), expires_at), do: :open, else: :expired)

  defp state("expired", _expires_at), do: :expired
  defp state("revoked", _expires_at), do: :withdrawn
  defp state("accepted", _expires_at), do: :used
  defp state("declined", _expires_at), do: :declined

  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_utc(at), do: at
end
