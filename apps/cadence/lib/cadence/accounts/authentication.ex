defmodule Cadence.Accounts.Authentication do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Accounts.{
    OrganizationMembershipRow,
    Password,
    Token,
    User,
    UserLocalCredentialRow,
    UserRow,
    UserSessionTokenRow
  }

  alias Cadence.Ids
  alias Cadence.Repo

  @environment_admin_provider_key "environment_admin"
  @environment_admin_user_id "user_environment_admin"
  @legacy_bootstrap_provider_key "bootstrap_env"
  @legacy_bootstrap_user_id "user_bootstrap_admin"
  @password_provider_key "password"
  @browser_session_context "browser"
  @default_environment_admin_display_name "Cadence Administrator"
  @default_browser_session_ttl_seconds 2_592_000

  @type user_session_context :: :browser

  @type issued_user_session :: %{
          user: User.t(),
          session_token: binary(),
          expires_at: DateTime.t(),
          current_organization_id: binary() | nil,
          admin_mode?: boolean()
        }

  @spec environment_admin_enabled?() :: boolean()
  def environment_admin_enabled? do
    config = environment_admin_config()

    Keyword.get(config, :enabled, false) and
      present?(Keyword.get(config, :email)) and
      present?(Keyword.get(config, :password))
  end

  @spec reconcile_environment_admin() :: {:ok, User.t() | nil} | {:error, term()}
  def reconcile_environment_admin do
    Repo.transaction(&reconcile_environment_admin_transaction/0)
  end

  @spec sign_in(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    if environment_admin_email?(email) do
      login_environment_admin(email, password)
    else
      login_user(email, password)
    end
  end

  @spec login_environment_admin(binary(), binary()) ::
          {:ok, issued_user_session()} | {:error, term()}
  def login_environment_admin(email, password)
      when is_binary(email) and is_binary(password) do
    with :ok <- ensure_environment_admin_enabled(),
         true <- environment_admin_email?(email),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             user_id: @environment_admin_user_id,
             lifecycle_state: Atom.to_string(:active)
           ),
         %User{} = user <- UserRow.to_domain(user_row),
         :ok <- verify_environment_admin_password(user, password) do
      issue_user_session(user, @browser_session_context, nil, admin_mode?: true)
    else
      nil -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, _reason} = error -> error
    end
  end

  @spec login_user(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def login_user(email, password) when is_binary(email) and is_binary(password) do
    with {:ok, %User{} = user} <- fetch_active_user_by_email(email),
         :ok <- ensure_durable_login_user(user),
         :ok <- verify_durable_password(user, password) do
      issue_user_session(
        user,
        @browser_session_context,
        default_user_organization_id(user.user_id)
      )
    end
  end

  @spec verify_user_password(User.t(), binary()) :: :ok | {:error, :invalid_credentials}
  def verify_user_password(%User{user_id: @environment_admin_user_id} = user, password)
      when is_binary(password) do
    verify_environment_admin_password(user, password)
  end

  def verify_user_password(%User{} = user, password) when is_binary(password) do
    case ensure_durable_login_user(user) do
      :ok -> verify_durable_password(user, password)
      {:error, :invalid_credentials} = error -> error
    end
  end

  @spec authenticate_user_session(binary()) ::
          {:ok, %{user: User.t(), session_context: user_session_context()}} | {:error, term()}
  def authenticate_user_session(session_token) when is_binary(session_token) do
    with %UserSessionTokenRow{} = token_row <- active_session_token_row(session_token),
         {:ok, session_context} <- normalize_session_context(token_row.context),
         :ok <- ensure_session_principal_available(token_row.user_id),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             user_id: token_row.user_id,
             lifecycle_state: Atom.to_string(:active)
           ) do
      {:ok, %{user: UserRow.to_domain(user_row), session_context: session_context}}
    else
      nil -> {:error, :unauthenticated}
      {:error, _reason} = error -> error
    end
  end

  @spec revoke_user_session(binary()) :: :ok
  def revoke_user_session(session_token) when is_binary(session_token) do
    token_digest = Token.digest(session_token)

    UserSessionTokenRow
    |> where([row], row.token_digest == ^token_digest)
    |> Repo.delete_all()

    :ok
  end

  @spec durable_user_by_email(binary()) :: {:ok, User.t()} | :not_found
  def durable_user_by_email(email) when is_binary(email) do
    case Repo.get_by(UserRow, email: User.normalize_email(email)) do
      %UserRow{} = row ->
        user = UserRow.to_domain(row)

        if durable_user?(user) do
          {:ok, user}
        else
          :not_found
        end

      nil ->
        :not_found
    end
  end

  @spec upsert_user(Ecto.Repo.t(), User.t()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def upsert_user(repo, %User{} = user) do
    case repo.get_by(UserRow, email: user.email) do
      nil ->
        case repo.insert(UserRow.changeset(user)) do
          {:ok, %UserRow{} = row} -> {:ok, UserRow.to_domain(row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end

      %UserRow{} = row ->
        attrs = %{
          email: user.email,
          display_name: user.display_name,
          capabilities: Enum.map(user.capabilities, &Atom.to_string/1),
          confirmed_at: user.confirmed_at,
          lifecycle_state: Atom.to_string(user.lifecycle_state),
          metadata: user.metadata
        }

        case repo.update(UserRow.update_changeset(row, attrs)) do
          {:ok, %UserRow{} = updated_row} -> {:ok, UserRow.to_domain(updated_row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  @spec upsert_password_credential(Ecto.Repo.t(), binary(), binary(), map()) ::
          :ok | {:error, Changeset.t()}
  def upsert_password_credential(repo, user_id, password, metadata)
      when is_binary(user_id) and is_binary(password) and is_map(metadata) do
    upsert_local_credential(repo, user_id, @password_provider_key, password, metadata)
  end

  @spec revoke_all_user_sessions(Ecto.Repo.t(), binary()) :: :ok
  def revoke_all_user_sessions(repo, user_id) when is_binary(user_id) do
    UserSessionTokenRow
    |> where([row], row.user_id == ^user_id)
    |> repo.delete_all()

    :ok
  end

  @spec issue_browser_session(User.t(), binary() | nil) ::
          {:ok, issued_user_session()} | {:error, Changeset.t()}
  def issue_browser_session(%User{} = user, current_organization_id) do
    issue_user_session(user, @browser_session_context, current_organization_id)
  end

  defp persist_environment_admin(config) when is_list(config) do
    email = config |> Keyword.fetch!(:email) |> User.normalize_email()
    display_name = Keyword.get(config, :display_name, @default_environment_admin_display_name)
    password = Keyword.fetch!(config, :password)

    user =
      User.new(%{
        user_id: @environment_admin_user_id,
        email: email,
        display_name: display_name,
        capabilities: [:platform_admin],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{"environment_admin" => true}
      })

    with {:ok, persisted_user} <- upsert_environment_admin_user(user),
         :ok <-
           upsert_local_credential(
             Repo,
             persisted_user.user_id,
             @environment_admin_provider_key,
             password,
             %{"environment_admin" => true}
           ) do
      {:ok, persisted_user}
    end
  end

  defp reconcile_environment_admin_transaction do
    remove_legacy_bootstrap_admin()

    if environment_admin_enabled?() do
      case persist_environment_admin(environment_admin_config()) do
        {:ok, %User{} = user} -> user
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      :ok = remove_environment_admin()
      nil
    end
  end

  defp upsert_environment_admin_user(%User{} = user) do
    case Repo.get(UserRow, @environment_admin_user_id) do
      nil ->
        case Repo.insert(UserRow.changeset(user)) do
          {:ok, %UserRow{} = row} -> {:ok, UserRow.to_domain(row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end

      %UserRow{} = row ->
        attrs = %{
          email: user.email,
          display_name: user.display_name,
          capabilities: [Atom.to_string(:platform_admin)],
          confirmed_at: user.confirmed_at,
          lifecycle_state: Atom.to_string(:active),
          metadata: user.metadata
        }

        case Repo.update(UserRow.update_changeset(row, attrs)) do
          {:ok, %UserRow{} = updated_row} -> {:ok, UserRow.to_domain(updated_row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  defp remove_environment_admin do
    case Repo.get(UserRow, @environment_admin_user_id) do
      %UserRow{} = row ->
        case Repo.delete(row) do
          {:ok, %UserRow{}} -> :ok
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end

      nil ->
        :ok
    end
  end

  defp remove_legacy_bootstrap_admin do
    legacy_credential =
      Repo.get_by(UserLocalCredentialRow,
        user_id: @legacy_bootstrap_user_id,
        provider_key: @legacy_bootstrap_provider_key
      )

    case {Repo.get(UserRow, @legacy_bootstrap_user_id), legacy_credential} do
      {%UserRow{} = row, %UserLocalCredentialRow{}} ->
        case Repo.delete(row) do
          {:ok, %UserRow{}} -> :ok
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
        end

      _other ->
        :ok
    end
  end

  defp ensure_environment_admin_enabled do
    if environment_admin_enabled?(), do: :ok, else: {:error, :invalid_credentials}
  end

  defp ensure_session_principal_available(@environment_admin_user_id),
    do: ensure_environment_admin_enabled()

  defp ensure_session_principal_available(_user_id), do: :ok

  defp ensure_durable_login_user(%User{} = user) do
    cond do
      user.user_id == @environment_admin_user_id ->
        {:error, :invalid_credentials}

      user.lifecycle_state != :active ->
        {:error, :invalid_credentials}

      not User.confirmed?(user) ->
        {:error, :invalid_credentials}

      true ->
        :ok
    end
  end

  defp verify_environment_admin_password(%User{user_id: @environment_admin_user_id}, password) do
    with :ok <- ensure_environment_admin_enabled(),
         %UserLocalCredentialRow{} = credential_row <-
           active_local_credential(@environment_admin_user_id, @environment_admin_provider_key),
         true <- verify_password(password, credential_row) do
      :ok
    else
      _other -> {:error, :invalid_credentials}
    end
  end

  defp verify_environment_admin_password(%User{}, _password),
    do: {:error, :invalid_credentials}

  defp verify_durable_password(%User{user_id: user_id}, password) do
    with %UserLocalCredentialRow{} = credential_row <-
           active_local_credential(user_id, @password_provider_key),
         true <- verify_password(password, credential_row) do
      :ok
    else
      _other -> {:error, :invalid_credentials}
    end
  end

  defp verify_password(password, credential_row) do
    Password.verify_password(
      password,
      credential_row.password_hash,
      credential_row.password_salt,
      credential_row.password_iterations
    )
  end

  defp durable_user?(%User{} = user) do
    user.user_id != @environment_admin_user_id and user.lifecycle_state == :active and
      User.confirmed?(user) and active_password_credential?(user.user_id)
  end

  defp active_password_credential?(user_id) when is_binary(user_id) do
    not is_nil(active_local_credential(user_id, @password_provider_key))
  end

  defp active_local_credential(user_id, provider_key) do
    Repo.get_by(UserLocalCredentialRow,
      user_id: user_id,
      provider_key: provider_key,
      lifecycle_state: Atom.to_string(:active)
    )
  end

  defp fetch_active_user_by_email(email) when is_binary(email) do
    normalized_email = User.normalize_email(email)

    case Repo.get_by(UserRow,
           email: normalized_email,
           lifecycle_state: Atom.to_string(:active)
         ) do
      %UserRow{} = row -> {:ok, UserRow.to_domain(row)}
      nil -> {:error, :invalid_credentials}
    end
  end

  defp default_user_organization_id(user_id) when is_binary(user_id) do
    OrganizationMembershipRow
    |> where(
      [row],
      row.user_id == ^user_id and row.lifecycle_state == ^Atom.to_string(:active)
    )
    |> order_by([row], asc: row.inserted_at, asc: row.organization_id)
    |> limit(1)
    |> Repo.one()
    |> case do
      %OrganizationMembershipRow{} = row -> row.organization_id
      nil -> nil
    end
  end

  defp upsert_local_credential(repo, user_id, provider_key, password, metadata)
       when is_binary(user_id) and is_binary(provider_key) and is_binary(password) and
              is_map(metadata) do
    attrs = local_credential_attrs(user_id, provider_key, password, metadata)

    case repo.get_by(UserLocalCredentialRow, user_id: user_id, provider_key: provider_key) do
      nil -> insert_local_credential(repo, attrs)
      %UserLocalCredentialRow{} = row -> update_local_credential(repo, row, attrs)
    end
  end

  defp active_session_token_row(session_token) do
    token_digest = Token.digest(session_token)

    UserSessionTokenRow
    |> where([row], row.token_digest == ^token_digest and row.expires_at > ^DateTime.utc_now())
    |> Repo.one()
  end

  defp issue_user_session(user, session_context, current_organization_id, opts \\ [])
       when is_list(opts) do
    session_token = Token.generate()
    expires_at = DateTime.utc_now() |> DateTime.add(@default_browser_session_ttl_seconds, :second)

    attrs = %{
      session_token_id: Ids.new("sess"),
      user_id: user.user_id,
      context: session_context,
      token_digest: Token.digest(session_token),
      token_hint: Token.hint(session_token),
      expires_at: expires_at,
      metadata: %{}
    }

    case Repo.insert(UserSessionTokenRow.changeset(attrs)) do
      {:ok, %UserSessionTokenRow{}} ->
        {:ok,
         %{
           user: user,
           session_token: session_token,
           expires_at: expires_at,
           current_organization_id: current_organization_id,
           admin_mode?: Keyword.get(opts, :admin_mode?, false)
         }}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp normalize_session_context(@browser_session_context), do: {:ok, :browser}
  defp normalize_session_context(_other), do: {:error, :unauthenticated}

  defp environment_admin_config do
    Application.get_env(:cadence, :environment_admin, [])
  end

  defp environment_admin_email?(email) when is_binary(email) do
    environment_admin_enabled?() and
      User.normalize_email(email) ==
        environment_admin_config() |> Keyword.fetch!(:email) |> User.normalize_email()
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp local_credential_attrs(user_id, provider_key, password, metadata) do
    password_document = Password.hash_password(password)

    %{
      local_credential_id: Ids.new("cred"),
      user_id: user_id,
      provider_key: provider_key,
      password_hash: password_document.password_hash,
      password_salt: password_document.password_salt,
      password_iterations: password_document.password_iterations,
      lifecycle_state: Atom.to_string(:active),
      metadata: metadata
    }
  end

  defp insert_local_credential(repo, attrs) when is_map(attrs) do
    case repo.insert(UserLocalCredentialRow.changeset(attrs)) do
      {:ok, %UserLocalCredentialRow{}} -> :ok
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp update_local_credential(repo, %UserLocalCredentialRow{} = row, attrs)
       when is_map(attrs) do
    case repo.update(
           UserLocalCredentialRow.update_changeset(
             row,
             Map.drop(attrs, [:local_credential_id, :user_id, :provider_key])
           )
         ) do
      {:ok, %UserLocalCredentialRow{}} -> :ok
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end
end
