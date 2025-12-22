defmodule Cadence.Application.Accounts.MagicLinkOperations do
  @moduledoc """
  Use case module for magic link authentication operations.

  Provides operations for generating and verifying magic link tokens
  for passwordless login.

  ## Usage

      # Generate a magic link token for a user
      {:ok, url_token} = MagicLinkOperations.generate(user_id)

      # Verify a magic link token (from URL)
      {:ok, user} = MagicLinkOperations.verify(url_token)
  """

  alias Cadence.Domain.Accounts.Entities.User
  alias Cadence.Domain.Accounts.Entities.UserToken
  alias Cadence.Application.Accounts.UserQueries

  @type user_id :: String.t()
  @type url_token :: String.t()

  # Get configured repository
  defp token_repo do
    Cadence.Ports.Repository.Accounts.TokenRepository.impl()
  end

  # ===========================================================================
  # Magic Link Generation
  # ===========================================================================

  @doc """
  Generates a magic link login token for a user.

  Returns `{:ok, url_token}` where `url_token` is the base64-encoded token
  to include in the login URL.

  The token is valid for 15 minutes and is single-use.
  """
  @spec generate(user_id()) :: {:ok, url_token()} | {:error, term()}
  def generate(user_id) do
    with {:ok, user} <- UserQueries.find(user_id) do
      generate_for_user(user)
    end
  end

  @doc """
  Generates a magic link token for a user entity.
  """
  @spec generate_for_user(User.t()) :: {:ok, url_token()} | {:error, term()}
  def generate_for_user(%User{id: user_id, email: email}) do
    {url_token, token_entity} = UserToken.build_login_token(user_id, email)

    case token_repo().save(token_entity) do
      {:ok, _saved} -> {:ok, url_token}
      error -> error
    end
  end

  @doc """
  Generates a magic link token by email.

  If the user exists, generates and returns a token.
  If the user does not exist, returns `{:error, :not_found}`.

  Note: In production, you may want to always return success to prevent
  email enumeration attacks. The caller can decide how to handle this.
  """
  @spec generate_for_email(String.t()) :: {:ok, url_token()} | {:error, :not_found}
  def generate_for_email(email) do
    case UserQueries.find_by_email(email) do
      {:ok, user} -> generate_for_user(user)
      error -> error
    end
  end

  # ===========================================================================
  # Magic Link Verification
  # ===========================================================================

  @doc """
  Verifies a magic link token and returns the associated user.

  Returns `{:ok, user}` if the token is valid, not expired, and matches
  the user's current email.

  Note: This does NOT consume the token. Call `consume/1` after successful
  verification to prevent token reuse.
  """
  @spec verify(url_token()) :: {:ok, User.t()} | {:error, :invalid_token | :expired | :not_found}
  def verify(url_token) do
    case UserToken.verify_login_token(url_token) do
      {:ok, hashed_token} ->
        token_repo().find_user_by_login_token(hashed_token)

      :error ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Verifies a magic link token and deletes it (single-use).

  This is the recommended way to use magic links - verify and consume in one step.
  """
  @spec verify_and_consume(url_token()) ::
          {:ok, User.t()} | {:error, :invalid_token | :expired | :not_found}
  def verify_and_consume(url_token) do
    with {:ok, user} <- verify(url_token) do
      # Delete all login tokens for this user to prevent reuse
      consume(user.id)
      {:ok, user}
    end
  end

  @doc """
  Consumes (deletes) all magic link tokens for a user.

  Call this after successful authentication to prevent token reuse.
  """
  @spec consume(user_id()) :: :ok
  def consume(user_id) do
    token_repo().delete_all_login_tokens_for_user(user_id)
  end

  # ===========================================================================
  # Email Change Tokens
  # ===========================================================================

  @doc """
  Generates a token for email change confirmation.

  The token is sent to the new email address and, when verified,
  confirms the user wants to change their email to this address.
  """
  @spec generate_change_email_token(user_id(), String.t()) ::
          {:ok, url_token()} | {:error, term()}
  def generate_change_email_token(user_id, new_email) do
    with {:ok, _user} <- UserQueries.find(user_id) do
      {url_token, token_entity} = UserToken.build_change_email_token(user_id, new_email)

      case token_repo().save(token_entity) do
        {:ok, _saved} -> {:ok, url_token}
        error -> error
      end
    end
  end

  @doc """
  Verifies an email change token.

  Returns `{:ok, new_email}` if the token is valid and not expired.
  """
  @spec verify_change_email_token(url_token(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def verify_change_email_token(url_token, context) do
    with {:ok, hashed_token} <- decode_token(url_token),
         {:ok, token_entity} <- token_repo().find_change_email_token(hashed_token, context) do
      UserToken.extract_new_email(token_entity)
    end
  end

  @doc """
  Consumes (deletes) all email change tokens for a user.
  """
  @spec consume_change_email_tokens(user_id()) :: :ok
  def consume_change_email_tokens(user_id) do
    token_repo().delete_all_change_email_tokens_for_user(user_id)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp decode_token(url_token) do
    case UserToken.verify_change_email_token(url_token) do
      {:ok, hashed} -> {:ok, hashed}
      :error -> {:error, :invalid_token}
    end
  end
end
