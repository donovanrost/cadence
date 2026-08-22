defmodule Cadence.Accounts do
  @moduledoc """
  The Accounts context - facade for user and authentication operations.

  This module delegates to hexagonal architecture application services:

  - `Cadence.Application.Accounts.UserQueries` - User read operations
  - `Cadence.Application.Accounts.UserOperations` - User write operations
  - `Cadence.Application.Accounts.SessionOperations` - Session management
  - `Cadence.Application.Accounts.MagicLinkOperations` - Magic link authentication

  ## Domain Entities

  All functions return domain entities from `Cadence.Domain.Accounts.Entities.*`,
  not Ecto schemas.

  ## Usage

      # Find a user
      {:ok, user} = Accounts.get_user(id)

      # Authenticate
      {:ok, user} = Accounts.get_user_by_email_and_password(email, password)

      # Create session
      token = Accounts.generate_user_session_token(user)

  ## Form Helpers

  Some functions return Ecto changesets for Phoenix form compatibility.
  These are clearly marked in the documentation.
  """

  alias Cadence.Domain.Accounts.Entities.User, as: UserEntity
  alias Cadence.Domain.Accounts.Entities.UserToken, as: UserTokenEntity

  # Application services
  alias Cadence.Application.Accounts.MagicLinkOperations
  alias Cadence.Application.Accounts.SessionOperations
  alias Cadence.Application.Accounts.UserOperations
  alias Cadence.Application.Accounts.UserQueries

  # Ecto schemas needed for form helpers and email delivery
  alias Cadence.Accounts.User, as: UserSchema
  alias Cadence.Accounts.UserNotifier
  alias Cadence.Time, as: CadenceTime

  # ============================================================================
  # User Queries
  # ============================================================================

  @doc """
  Returns the list of all users in the system.
  """
  @spec list_all_users() :: [UserEntity.t()]
  def list_all_users do
    UserQueries.list()
  end

  @doc """
  Alias for list_all_users/0.
  """
  @spec list_users() :: [UserEntity.t()]
  def list_users, do: list_all_users()

  @doc """
  Gets a user by ID.

  Returns `{:ok, user}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_user(String.t()) :: {:ok, UserEntity.t()} | {:error, :not_found}
  def get_user(id), do: UserQueries.find(id)

  @doc """
  Gets a user by ID, raising if not found.
  """
  @spec get_user!(String.t()) :: UserEntity.t()
  def get_user!(id), do: UserQueries.find!(id)

  @doc """
  Gets a single user with organization memberships preloaded.

  Raises if the User does not exist.

  Note: This function returns an Ecto schema (not a domain entity) because
  it includes preloaded associations. Consider refactoring callers to
  fetch memberships separately via the Organizations context.
  """
  @spec get_user_with_memberships!(String.t()) :: UserSchema.t()
  def get_user_with_memberships!(id) do
    alias Cadence.Repo

    UserSchema
    |> Repo.get!(id)
    |> Repo.preload(:organization_memberships)
  end

  @doc """
  Gets a user by email.
  """
  @spec get_user_by_email(String.t()) :: UserEntity.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    case UserQueries.find_by_email(email) do
      {:ok, user} -> user
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Gets a user by email and password.

  Returns the user if credentials are valid, nil otherwise.
  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: UserEntity.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    case SessionOperations.authenticate_by_password(email, password) do
      {:ok, user} -> user
      {:error, :invalid_credentials} -> nil
    end
  end

  # ============================================================================
  # User Registration
  # ============================================================================

  @doc """
  Registers a user.

  Note: Organization membership should be handled separately by the caller
  if needed.
  """
  @spec register_user(map()) :: {:ok, UserEntity.t()} | {:error, term()}
  def register_user(attrs) do
    # Normalize string keys to atoms
    attrs = normalize_attrs(attrs)
    UserOperations.register(attrs)
  end

  @doc """
  Ensures a system admin user exists with the given email and password.

  This function is idempotent and safe to call on every application start.
  """
  @spec ensure_system_admin(String.t(), String.t()) :: {:ok, UserEntity.t()} | {:error, term()}
  def ensure_system_admin(email, password) when is_binary(email) and is_binary(password) do
    UserOperations.ensure_system_admin(email, password)
  end

  # ============================================================================
  # Sudo Mode
  # ============================================================================

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.

  Accepts both domain entities and Ecto schemas for backward compatibility.
  """
  @spec sudo_mode?(UserEntity.t() | UserSchema.t(), integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  # Handle Ecto schema with authenticated_at
  def sudo_mode?(%UserSchema{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, CadenceTime.now() |> DateTime.add(minutes, :minute))
  end

  # Domain entities don't have authenticated_at - this needs session context
  def sudo_mode?(%UserEntity{} = _user, _minutes), do: false

  def sudo_mode?(_user, _minutes), do: false

  # ============================================================================
  # Password Management
  # ============================================================================

  @doc """
  Updates the user password.

  Returns `{:ok, {user, expired_tokens}}` on success.

  Accepts domain entities, Ecto schemas, or user IDs.
  """
  @spec update_user_password(UserEntity.t() | UserSchema.t() | String.t(), map()) ::
          {:ok, {UserEntity.t(), [UserTokenEntity.t()]}} | {:error, term()}
  def update_user_password(%UserEntity{id: user_id}, attrs) do
    update_user_password(user_id, attrs)
  end

  def update_user_password(%UserSchema{id: user_id}, attrs) do
    update_user_password(user_id, attrs)
  end

  def update_user_password(user_id, attrs) when is_binary(user_id) do
    password = attrs[:password] || attrs["password"]

    with {:ok, user} <- UserOperations.set_password(user_id, password),
         {:ok, expired_tokens} <- SessionOperations.delete_all_tokens(user_id) do
      {:ok, {user, expired_tokens}}
    end
  end

  # ============================================================================
  # Session Management
  # ============================================================================

  @doc """
  Generates a session token for a user.

  Accepts domain entities, Ecto schemas, or user IDs.
  """
  @spec generate_user_session_token(UserEntity.t() | UserSchema.t() | String.t()) :: binary()
  def generate_user_session_token(%UserEntity{id: user_id}),
    do: generate_user_session_token(user_id)

  def generate_user_session_token(%UserSchema{id: user_id}),
    do: generate_user_session_token(user_id)

  def generate_user_session_token(user_id) when is_binary(user_id) do
    case SessionOperations.create_session_token(user_id) do
      {:ok, token} -> token
      {:error, _} -> raise "Failed to generate session token"
    end
  end

  @doc """
  Gets the user with the given signed session token.

  Returns `{user, token_inserted_at}` if valid, nil otherwise.
  """
  @spec get_user_by_session_token(binary()) :: {UserEntity.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    case SessionOperations.validate_session_with_timestamp(token) do
      {:ok, user, authenticated_at} -> {user, authenticated_at}
      {:error, _} -> nil
    end
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    SessionOperations.delete_session(token)
  end

  # ============================================================================
  # Magic Link Authentication
  # ============================================================================

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(String.t()) :: UserEntity.t() | nil
  def get_user_by_magic_link_token(token) do
    case MagicLinkOperations.verify(token) do
      {:ok, user} -> user
      {:error, _} -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  Handles confirmation for new users and token expiration.
  Returns `{:ok, {user, expired_tokens}}` on success.
  """
  @spec login_user_by_magic_link(String.t()) ::
          {:ok, {UserEntity.t(), [UserTokenEntity.t()]}} | {:error, :not_found}
  def login_user_by_magic_link(token) do
    MagicLinkOperations.login(token)
  end

  @doc """
  Generates a magic link token for a user.
  """
  @spec generate_magic_link(String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_magic_link(user_id), do: MagicLinkOperations.generate(user_id)

  @doc """
  Verifies and consumes a magic link token.
  """
  @spec verify_magic_link(String.t()) :: {:ok, UserEntity.t()} | {:error, term()}
  def verify_magic_link(url_token), do: MagicLinkOperations.verify_and_consume(url_token)

  # ============================================================================
  # Email Delivery
  # ============================================================================

  @doc """
  Delivers the update email instructions to the given user.

  The `user.email` should contain the NEW email address to change to.
  The `current_email` parameter is used to construct the change email context.
  """
  def deliver_user_update_email_instructions(user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    # Generate change email token:
    # - current_email is used for context verification
    # - user.email contains the NEW email to change to (stored in sent_to)
    case MagicLinkOperations.generate_change_email_token(user.id, current_email, user.email) do
      {:ok, encoded_token} ->
        # Need to work with schema for email delivery
        user_schema = domain_to_schema(user)

        UserNotifier.deliver_update_email_instructions(
          user_schema,
          update_email_url_fun.(encoded_token)
        )

      error ->
        error
    end
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    user = ensure_domain_user(user)

    case MagicLinkOperations.generate_for_user(user) do
      {:ok, encoded_token} ->
        user_schema = domain_to_schema(user)
        UserNotifier.deliver_login_instructions(user_schema, magic_link_url_fun.(encoded_token))

      error ->
        error
    end
  end

  # ============================================================================
  # Form Helpers (Ecto Schema Layer)
  #
  # These functions return Ecto changesets for Phoenix form compatibility.
  # They work with Ecto schemas, not domain entities.
  # ============================================================================

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  This is a form helper that works with Ecto schemas.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    user_schema = ensure_schema(user)
    UserSchema.email_changeset(user_schema, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  This is a form helper that works with Ecto schemas.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    user_schema = ensure_schema(user)
    UserSchema.password_changeset(user_schema, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    case MagicLinkOperations.verify_change_email_token(token, context) do
      {:ok, new_email} ->
        with {:ok, updated} <- UserOperations.update_email(user.id, new_email) do
          MagicLinkOperations.consume_change_email_tokens(user.id)
          {:ok, updated}
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {k, v}, acc when is_binary(k) ->
        atom_key = String.to_existing_atom(k)
        Map.put(acc, atom_key, v)

      {k, v}, acc when is_atom(k) ->
        Map.put(acc, k, v)
    end)
  rescue
    ArgumentError -> attrs
  end

  # Convert domain entity to Ecto schema for email delivery
  defp domain_to_schema(%UserEntity{} = user) do
    %UserSchema{
      id: user.id,
      email: user.email,
      confirmed_at: user.confirmed_at,
      hashed_password: user.hashed_password
    }
  end

  defp domain_to_schema(%UserSchema{} = schema), do: schema

  # Ensure we have an Ecto schema for form helpers
  defp ensure_schema(%UserEntity{} = user), do: domain_to_schema(user)
  defp ensure_schema(%UserSchema{} = schema), do: schema
  defp ensure_schema(%{} = attrs), do: struct(UserSchema, attrs)

  defp ensure_domain_user(%UserEntity{} = user), do: user

  defp ensure_domain_user(%UserSchema{id: user_id}) do
    UserQueries.find!(user_id)
  end
end
