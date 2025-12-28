defmodule Cadence.Application.Accounts.SessionOperations do
  @moduledoc """
  Use case module for user session operations.

  Provides operations for creating and managing user sessions.

  ## Usage

      # Create a session for a user
      {:ok, token, user} = SessionOperations.create_session(user_id)

      # Validate a session token
      {:ok, user} = SessionOperations.validate_session(token)

      # Delete a session (logout)
      :ok = SessionOperations.delete_session(token)
  """

  alias Cadence.Application.Accounts.UserQueries
  alias Cadence.Domain.Accounts.Entities.User
  alias Cadence.Domain.Accounts.Entities.UserToken
  alias Cadence.Ports.Repository.Accounts.TokenRepository
  alias Cadence.Ports.Security.PasswordHasher

  @type user_id :: String.t()
  @type token :: binary()

  # Get configured repository
  defp token_repo do
    TokenRepository.impl()
  end

  # ===========================================================================
  # Password Authentication
  # ===========================================================================

  @doc """
  Authenticates a user by email and password.

  Returns `{:ok, user}` if credentials are valid, `{:error, :invalid_credentials}` otherwise.

  ## Security

  This function uses constant-time comparison and performs dummy
  verification when the user is not found to prevent timing attacks.
  """
  @spec authenticate_by_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials}
  def authenticate_by_password(email, password) do
    case UserQueries.find_by_email(email) do
      {:ok, user} ->
        if verify_password(user, password) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end

      {:error, :not_found} ->
        # Prevent timing attacks by doing dummy verification
        PasswordHasher.dummy_verify()
        {:error, :invalid_credentials}
    end
  end

  # ===========================================================================
  # Session Management
  # ===========================================================================

  @doc """
  Creates a new session for a user.

  Returns `{raw_token, user}` where:
  - `raw_token` is the token to store in the session cookie
  - `user` is the user entity with authenticated_at set
  """
  @spec create_session(user_id()) :: {:ok, token(), User.t()} | {:error, term()}
  def create_session(user_id) do
    with {:ok, user} <- UserQueries.find(user_id) do
      authenticated_at = DateTime.utc_now() |> DateTime.truncate(:second)
      {raw_token, token_entity} = UserToken.build_session_token(user_id, authenticated_at)

      case token_repo().save(token_entity) do
        {:ok, _saved} -> {:ok, raw_token, user}
        error -> error
      end
    end
  end

  @doc """
  Creates a session and returns just the token.

  Convenience wrapper around `create_session/1`.
  """
  @spec create_session_token(user_id()) :: {:ok, token()} | {:error, term()}
  def create_session_token(user_id) do
    case create_session(user_id) do
      {:ok, token, _user} -> {:ok, token}
      error -> error
    end
  end

  @doc """
  Validates a session token and returns the associated user.

  Returns `{:ok, user}` if the token is valid and not expired.
  """
  @spec validate_session(token()) :: {:ok, User.t()} | {:error, :not_found | :expired}
  def validate_session(token) do
    case token_repo().find_user_by_session_token(token) do
      {:ok, user, _authenticated_at} -> {:ok, user}
      error -> error
    end
  end

  @doc """
  Validates a session token and returns the user with authenticated_at.
  """
  @spec validate_session_with_timestamp(token()) ::
          {:ok, User.t(), DateTime.t()} | {:error, :not_found | :expired}
  def validate_session_with_timestamp(token) do
    token_repo().find_user_by_session_token(token)
  end

  @doc """
  Deletes a session by its token.
  """
  @spec delete_session(token()) :: :ok
  def delete_session(token) do
    token_repo().delete_by_token_and_context(token, "session")
  end

  @doc """
  Lists all active sessions for a user.
  """
  @spec list_sessions(user_id()) :: [UserToken.t()]
  def list_sessions(user_id), do: token_repo().list_sessions_for_user(user_id)

  @doc """
  Deletes all sessions for a user (logout from all devices).
  """
  @spec delete_all_sessions(user_id()) :: :ok
  def delete_all_sessions(user_id) do
    token_repo().delete_all_sessions_for_user(user_id)
  end

  @doc """
  Deletes all tokens for a user (all sessions, magic links, email change tokens).

  Returns the list of tokens that were deleted.

  Used when password is changed or user is confirmed via magic link.
  """
  @spec delete_all_tokens(user_id()) :: {:ok, [UserToken.t()]}
  def delete_all_tokens(user_id) do
    token_repo().delete_all_for_user(user_id)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp verify_password(%User{hashed_password: nil}, _password) do
    # User has no password set (passwordless account)
    false
  end

  defp verify_password(%User{hashed_password: hash}, password) do
    PasswordHasher.verify(password, hash)
  end
end
