defmodule Cadence.Accounts do
  @moduledoc """
  The Accounts context - facade for user and authentication operations.

  This module delegates to hexagonal architecture application services while
  maintaining backward compatibility with existing code that uses Ecto schemas.

  ## Architecture

  This context is built on hexagonal architecture with the following layers:

  - **Domain**: `Cadence.Domain.Accounts.Entities.*` - Pure business entities
  - **Ports**: `Cadence.Ports.Repository.Accounts.*` - Repository contracts
  - **Adapters**: `Cadence.Adapters.Persistence.Ecto.Accounts.*` - Ecto implementations
  - **Application**: `Cadence.Application.Accounts.*` - Use case orchestration

  ## For New Code

  Prefer using the application services directly:

      alias Cadence.Application.Accounts.{UserQueries, UserOperations, SessionOperations}

      # Find user
      {:ok, user} = UserQueries.find(id)

      # Authenticate
      {:ok, user} = SessionOperations.authenticate_by_password(email, password)

      # Create session
      {:ok, token, user} = SessionOperations.create_session(user_id)

  ## Legacy Support

  Functions in this module maintain backward compatibility with existing code
  that works with Ecto schemas directly.
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo

  alias Cadence.Accounts.{User, UserToken, UserNotifier}
  alias Cadence.Organizations.OrganizationMembership

  # Application services for new hexagonal architecture
  alias Cadence.Application.Accounts.UserQueries
  alias Cadence.Application.Accounts.UserOperations
  alias Cadence.Application.Accounts.SessionOperations
  alias Cadence.Application.Accounts.MagicLinkOperations

  ## Database getters

  @doc """
  Returns the list of all users in the system.

  ## Examples

      iex> list_all_users()
      [%User{}, ...]

  """
  def list_all_users do
    Repo.all(User)
  end

  @doc """
  Alias for list_all_users/0
  """
  def list_users, do: list_all_users()

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user with organization memberships preloaded.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user_with_memberships!(id) do
    User
    |> Repo.get!(id)
    |> Repo.preload(:organization_memberships)
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.email_changeset(%User{}, attrs))
    |> Ecto.Multi.run(:organization_membership, fn repo, %{user: user} ->
      # Create organization membership if organization_id is provided
      case Map.get(attrs, "organization_id") || Map.get(attrs, :organization_id) do
        nil ->
          {:ok, nil}

        org_id ->
          # Determine role: "owner" if they're creating the org, "admin" otherwise
          role = Map.get(attrs, "role") || Map.get(attrs, :role) || "admin"

          %OrganizationMembership{}
          |> OrganizationMembership.changeset(%{
            user_id: user.id,
            organization_id: org_id,
            role: role
          })
          |> repo.insert()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Ensures a system admin user exists with the given email and password.

  If the user already exists:
  - Updates the password if different
  - Ensures system_admin flag is true

  If the user doesn't exist:
  - Creates a new system admin user with confirmed email

  This function is idempotent and safe to call on every application start.
  """
  def ensure_system_admin(email, password) when is_binary(email) and is_binary(password) do
    case get_user_by_email(email) do
      nil ->
        create_system_admin(email, password)

      user ->
        update_system_admin(user, password)
    end
  end

  defp create_system_admin(email, password) do
    %User{}
    |> User.email_changeset(%{email: email, system_admin: true})
    |> User.password_changeset(%{password: password})
    |> User.confirm_changeset()
    |> Repo.insert()
  end

  defp update_system_admin(user, password) do
    changeset =
      user
      |> User.email_changeset(%{system_admin: true})
      |> User.password_changeset(%{password: password}, hash_password: true)

    case Repo.update(changeset) do
      {:ok, user} -> {:ok, user}
      {:error, _} = error -> error
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Cadence.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Cadence.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  # ===========================================================================
  # Domain Entity Access (New API - Returns Domain Entities)
  # ===========================================================================

  @doc """
  Finds a user and returns a domain entity.

  Use this when you want to work with the hexagonal architecture.
  """
  @spec find_user(String.t()) ::
          {:ok, Cadence.Domain.Accounts.Entities.User.t()} | {:error, :not_found}
  def find_user(id), do: UserQueries.find(id)

  @doc """
  Finds a user by email and returns a domain entity.
  """
  @spec find_user_by_email(String.t()) ::
          {:ok, Cadence.Domain.Accounts.Entities.User.t()} | {:error, :not_found}
  def find_user_by_email(email), do: UserQueries.find_by_email(email)

  @doc """
  Lists users as domain entities.
  """
  @spec list_users_as_entities(keyword()) :: [Cadence.Domain.Accounts.Entities.User.t()]
  def list_users_as_entities(opts \\ []), do: UserQueries.list(opts)

  @doc """
  Registers a user using the hexagonal architecture.

  Returns a domain entity.
  """
  @spec register_user_entity(map()) ::
          {:ok, Cadence.Domain.Accounts.Entities.User.t()} | {:error, term()}
  def register_user_entity(attrs), do: UserOperations.register(attrs)

  @doc """
  Authenticates a user by email and password using the hexagonal architecture.

  Returns a domain entity.
  """
  @spec authenticate_user(String.t(), String.t()) ::
          {:ok, Cadence.Domain.Accounts.Entities.User.t()} | {:error, :invalid_credentials}
  def authenticate_user(email, password) do
    SessionOperations.authenticate_by_password(email, password)
  end

  @doc """
  Creates a session using the hexagonal architecture.

  Returns `{:ok, token, user}` where user is a domain entity.
  """
  @spec create_session(String.t()) ::
          {:ok, binary(), Cadence.Domain.Accounts.Entities.User.t()} | {:error, term()}
  def create_session(user_id), do: SessionOperations.create_session(user_id)

  @doc """
  Validates a session token using the hexagonal architecture.

  Returns `{:ok, user}` where user is a domain entity.
  """
  @spec validate_session(binary()) ::
          {:ok, Cadence.Domain.Accounts.Entities.User.t()} | {:error, term()}
  def validate_session(token), do: SessionOperations.validate_session(token)

  @doc """
  Generates a magic link token for a user.

  Returns `{:ok, url_token}` where url_token is base64-encoded.
  """
  @spec generate_magic_link(String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_magic_link(user_id), do: MagicLinkOperations.generate(user_id)

  @doc """
  Verifies and consumes a magic link token.

  Returns `{:ok, user}` where user is a domain entity.
  """
  @spec verify_magic_link(String.t()) ::
          {:ok, Cadence.Domain.Accounts.Entities.User.t()} | {:error, term()}
  def verify_magic_link(url_token), do: MagicLinkOperations.verify_and_consume(url_token)
end
