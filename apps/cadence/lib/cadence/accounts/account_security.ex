defmodule Cadence.Accounts.AccountSecurity do
  @moduledoc """
  A signed-in user's own password and sessions (console Account).

  - Changing the password needs the current one, sets the new one (at least 12 characters, not
    the same as the current one) and signs out every **other** session of the user; the
    session making the change stays signed in. The environment admin's password comes from
    the environment and can't be changed here (`:password_managed_externally`).
  - Sessions: the user's unexpired sessions, newest first, marked `current` for the one asking.
    Revoking one signs it out (revoking the current one signs you out); revoking the others
    keeps only the current one.

  Sessions record no device or address, only when they started and when they expire.
  """

  import Ecto.Query

  alias Cadence.Accounts.{Authentication, Token, User, UserSessionTokenRow}
  alias Cadence.Repo

  @environment_admin "user_environment_admin"
  @min_password 12

  @spec change_password(User.t(), binary(), map()) ::
          :ok
          | {:error,
             :password_managed_externally | :invalid_credentials | {:invalid, map()} | term()}
  def change_password(%User{user_id: @environment_admin}, _current_token, _params),
    do: {:error, :password_managed_externally}

  def change_password(%User{} = user, current_token, params) do
    current = to_string(params["current_password"] || "")
    new = to_string(params["new_password"] || "")

    with :ok <- new_password(new, current),
         :ok <- Authentication.verify_user_password(user, current) do
      Repo.transaction(fn -> set_password(user.user_id, new, current_token) end)
      |> case do
        {:ok, _count} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec list_sessions(binary(), binary()) :: [map()]
  def list_sessions(user_id, current_token) do
    current = Token.digest(current_token)

    UserSessionTokenRow
    |> where([s], s.user_id == ^user_id and s.expires_at > ^DateTime.utc_now())
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.session_token_id,
        started_at: &1.inserted_at,
        expires_at: &1.expires_at,
        current: same_digest?(&1.token_digest, current)
      }
    )
  end

  @spec revoke_session(binary(), binary()) :: :ok | {:error, :session_not_found}
  def revoke_session(user_id, session_id) do
    {count, _rows} =
      UserSessionTokenRow
      |> where([s], s.user_id == ^user_id and s.session_token_id == ^session_id)
      |> Repo.delete_all()

    if count == 1, do: :ok, else: {:error, :session_not_found}
  end

  @doc "Signs out every session of the user except `current_token`'s; returns how many."
  @spec revoke_others(binary(), binary()) :: non_neg_integer()
  def revoke_others(user_id, current_token) do
    current = Token.digest(current_token)

    {count, _rows} =
      UserSessionTokenRow
      |> where([s], s.user_id == ^user_id and s.token_digest != ^current)
      |> Repo.delete_all()

    count
  end

  defp set_password(user_id, new, current_token) do
    metadata = %{"changed_at" => DateTime.to_iso8601(DateTime.utc_now())}

    case Authentication.upsert_password_credential(Repo, user_id, new, metadata) do
      :ok -> revoke_others(user_id, current_token)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp same_digest?(a, b) when byte_size(a) == byte_size(b), do: :crypto.hash_equals(a, b)
  defp same_digest?(_a, _b), do: false

  defp new_password(new, current) do
    cond do
      String.length(new) < @min_password ->
        {:error, {:invalid, %{new_password: "must be at least #{@min_password} characters"}}}

      new == current ->
        {:error, {:invalid, %{new_password: "must differ from the current password"}}}

      true ->
        :ok
    end
  end
end
