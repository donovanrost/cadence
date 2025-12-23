defmodule Cadence.Ports.Repository.Accounts.TokenRepository do
  @moduledoc """
  Port (behavior) defining the contract for user token persistence operations.

  Tokens are used for various authentication flows:
  - Session tokens for browser sessions
  - Magic link tokens for passwordless login
  - Email change confirmation tokens

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.Accounts.EctoTokenRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryTokenRepository` - In-memory for tests
  """

  alias Cadence.Domain.Accounts.Entities.UserToken
  alias Cadence.Domain.Accounts.Entities.User

  @type id :: String.t()
  @type user_id :: String.t()
  @type token :: binary()
  @type context :: String.t()
  @type opts :: keyword()
  @type error :: :not_found | term()

  # ============================================================================
  # Token CRUD Operations
  # ============================================================================

  @doc """
  Finds a token by ID.
  """
  @callback find(id()) :: {:ok, UserToken.t()} | {:error, :not_found}

  @doc """
  Finds a token by its value and context.

  For session tokens, the token is stored as-is.
  For hashed tokens (login, email change), the hashed version is looked up.
  """
  @callback find_by_token_and_context(token(), context()) ::
              {:ok, UserToken.t()} | {:error, :not_found}

  @doc """
  Saves a new token.

  Tokens are typically created fresh and not updated.
  """
  @callback save(UserToken.t()) :: {:ok, UserToken.t()} | {:error, error()}

  @doc """
  Deletes a token by ID.
  """
  @callback delete(id()) :: {:ok, UserToken.t()} | {:error, :not_found}

  @doc """
  Deletes a token by its value and context.
  """
  @callback delete_by_token_and_context(token(), context()) :: :ok

  # ============================================================================
  # Session Operations
  # ============================================================================

  @doc """
  Finds a user by their session token.

  Returns the user if the token is valid and not expired.
  Also returns the authenticated_at timestamp from the token.
  """
  @callback find_user_by_session_token(token()) ::
              {:ok, User.t(), DateTime.t()} | {:error, :not_found | :expired}

  @doc """
  Lists all session tokens for a user.

  Useful for displaying active sessions.
  """
  @callback list_sessions_for_user(user_id(), opts()) :: [UserToken.t()]

  @doc """
  Deletes all session tokens for a user.

  Used when user logs out from all devices.
  """
  @callback delete_all_sessions_for_user(user_id()) :: :ok

  # ============================================================================
  # Magic Link Operations
  # ============================================================================

  @doc """
  Finds a user by their magic link token.

  Returns the user if the token is valid, not expired, and matches the user's email.
  """
  @callback find_user_by_login_token(token()) :: {:ok, User.t()} | {:error, :not_found | :expired}

  @doc """
  Deletes all login tokens for a user.

  Used after successful login to prevent token reuse.
  """
  @callback delete_all_login_tokens_for_user(user_id()) :: :ok

  # ============================================================================
  # Email Change Operations
  # ============================================================================

  @doc """
  Finds a change email token by its hashed value and context.

  The context format is "change:new_email@example.com".
  """
  @callback find_change_email_token(token(), context()) ::
              {:ok, UserToken.t()} | {:error, :not_found | :expired}

  @doc """
  Deletes all email change tokens for a user.
  """
  @callback delete_all_change_email_tokens_for_user(user_id()) :: :ok

  # ============================================================================
  # Bulk Token Operations
  # ============================================================================

  @doc """
  Lists all tokens for a user.
  """
  @callback list_all_for_user(user_id()) :: [UserToken.t()]

  @doc """
  Deletes all tokens for a user and returns the deleted tokens.

  Used when password is changed or user is confirmed via magic link,
  to invalidate all existing sessions.
  """
  @callback delete_all_for_user(user_id()) :: {:ok, [UserToken.t()]}

  # ============================================================================
  # Cleanup Operations
  # ============================================================================

  @doc """
  Deletes all expired tokens.

  Should be run periodically to clean up the tokens table.
  """
  @callback delete_expired_tokens() :: {:ok, non_neg_integer()}

  # ============================================================================
  # Implementation Helper
  # ============================================================================

  @doc """
  Returns the configured token repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :token_repository,
      Cadence.Adapters.Persistence.Ecto.Accounts.EctoTokenRepository
    )
  end
end
