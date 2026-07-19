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

  @bootstrap_provider_key "bootstrap_env"
  @password_provider_key "password"
  @bootstrap_session_context "bootstrap_admin"
  @browser_session_context "browser"
  @default_bootstrap_admin_display_name "Bootstrap Admin"
  @default_bootstrap_admin_session_ttl_seconds 86_400
  @default_browser_session_ttl_seconds 2_592_000

  @type user_session_context :: :bootstrap_admin | :browser

  @type issued_user_session :: %{
          user: User.t(),
          session_token: binary(),
          expires_at: DateTime.t(),
          current_organization_id: binary() | nil
        }

  @spec bootstrap_admin_enabled?() :: boolean()
  def bootstrap_admin_enabled? do
    bootstrap_admin_config()
    |> Keyword.get(:enabled, false)
  end

  @spec ensure_bootstrap_admin() :: {:ok, User.t()} | {:error, term()}
  def ensure_bootstrap_admin do
    if bootstrap_admin_enabled?() do
      persist_bootstrap_admin(bootstrap_admin_config())
    else
      {:error, :bootstrap_admin_disabled}
    end
  end

  @spec sign_in(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def sign_in(email, password) when is_binary(email) and is_binary(password) do
    with {:ok, user} <- fetch_active_user_by_email(email),
         {:ok, credential_kind} <- resolve_credential_kind(user) do
      case credential_kind do
        :durable -> login_user(email, password)
        :bootstrap_admin -> login_bootstrap_admin(email, password)
      end
    end
  end

  @spec login_bootstrap_admin(binary(), binary()) ::
          {:ok, issued_user_session()} | {:error, term()}
  def login_bootstrap_admin(email, password)
      when is_binary(email) and is_binary(password) do
    with :ok <- ensure_bootstrap_admin_enabled(),
         normalized_email <- User.normalize_email(email),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             email: normalized_email,
             lifecycle_state: Atom.to_string(:active)
           ),
         {:ok, %User{} = user} <- ensure_platform_admin(UserRow.to_domain(user_row)),
         %UserLocalCredentialRow{} = credential_row <-
           Repo.get_by(UserLocalCredentialRow,
             user_id: user.user_id,
             provider_key: @bootstrap_provider_key,
             lifecycle_state: Atom.to_string(:active)
           ),
         true <-
           Password.verify_password(
             password,
             credential_row.password_hash,
             credential_row.password_salt,
             credential_row.password_iterations
           ) do
      issue_user_session(user, @bootstrap_session_context, nil)
    else
      nil -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, _reason} = error -> error
    end
  end

  @spec login_user(binary(), binary()) :: {:ok, issued_user_session()} | {:error, term()}
  def login_user(email, password) when is_binary(email) and is_binary(password) do
    with normalized_email <- User.normalize_email(email),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             email: normalized_email,
             lifecycle_state: Atom.to_string(:active)
           ),
         %User{} = user <- UserRow.to_domain(user_row),
         :ok <- ensure_durable_login_user(user),
         %UserLocalCredentialRow{} = credential_row <-
           Repo.get_by(UserLocalCredentialRow,
             user_id: user.user_id,
             provider_key: @password_provider_key,
             lifecycle_state: Atom.to_string(:active)
           ),
         true <-
           Password.verify_password(
             password,
             credential_row.password_hash,
             credential_row.password_salt,
             credential_row.password_iterations
           ) do
      issue_user_session(
        user,
        @browser_session_context,
        default_user_organization_id(user.user_id)
      )
    else
      nil -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, _reason} = error -> error
    end
  end

  @spec authenticate_user_session(binary()) ::
          {:ok, %{user: User.t(), session_context: user_session_context()}} | {:error, term()}
  def authenticate_user_session(session_token) when is_binary(session_token) do
    with %UserSessionTokenRow{} = token_row <- active_session_token_row(session_token),
         {:ok, session_context} <- normalize_session_context(token_row.context),
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
    case Repo.get_by(UserRow, email: email) do
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

  defp persist_bootstrap_admin(config) when is_list(config) do
    email = Keyword.fetch!(config, :email)
    display_name = Keyword.get(config, :display_name, @default_bootstrap_admin_display_name)
    password = Keyword.fetch!(config, :password)

    Repo.transaction(fn ->
      with {:ok, persisted_user} <- upsert_bootstrap_admin_user(email, display_name),
           :ok <-
             upsert_local_credential(
               Repo,
               persisted_user.user_id,
               @bootstrap_provider_key,
               password,
               setup_access_metadata()
             ) do
        persisted_user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, %User{} = persisted_user} -> {:ok, persisted_user}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_bootstrap_admin_enabled do
    if bootstrap_admin_enabled?(), do: :ok, else: {:error, :bootstrap_admin_disabled}
  end

  defp ensure_platform_admin(%User{} = user) do
    if :platform_admin in user.capabilities do
      {:ok, user}
    else
      {:error, :forbidden}
    end
  end

  defp ensure_durable_login_user(%User{} = user) do
    cond do
      user.lifecycle_state != :active ->
        {:error, :invalid_credentials}

      not User.confirmed?(user) ->
        {:error, :invalid_credentials}

      true ->
        :ok
    end
  end

  defp upsert_bootstrap_admin_user(email, display_name) do
    normalized_email = User.normalize_email(email)

    case Repo.get_by(UserRow, email: normalized_email) do
      nil ->
        user =
          User.new(%{
            user_id: bootstrap_admin_config() |> Keyword.get(:user_id, "user_bootstrap_admin"),
            email: normalized_email,
            display_name: display_name,
            capabilities: [:platform_admin],
            lifecycle_state: :active,
            metadata: setup_access_metadata()
          })

        upsert_user(Repo, user)

      %UserRow{} = row ->
        existing_user = UserRow.to_domain(row)

        user =
          User.new(%{
            user_id: existing_user.user_id,
            email: existing_user.email,
            display_name:
              if(User.confirmed?(existing_user),
                do: existing_user.display_name,
                else: display_name
              ),
            capabilities: add_platform_admin_capability(existing_user.capabilities),
            confirmed_at: existing_user.confirmed_at,
            lifecycle_state: :active,
            metadata:
              if(User.confirmed?(existing_user),
                do: existing_user.metadata,
                else: Map.merge(existing_user.metadata, setup_access_metadata())
              )
          })

        upsert_user(Repo, user)
    end
  end

  defp durable_user?(%User{} = user) do
    user.lifecycle_state == :active and User.confirmed?(user) and
      active_password_credential?(user.user_id)
  end

  defp active_password_credential?(user_id) when is_binary(user_id) do
    Repo.get_by(UserLocalCredentialRow,
      user_id: user_id,
      provider_key: @password_provider_key,
      lifecycle_state: Atom.to_string(:active)
    ) != nil
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

  defp resolve_credential_kind(%User{user_id: user_id}) do
    has_password = active_credential?(user_id, @password_provider_key)
    has_bootstrap = active_credential?(user_id, @bootstrap_provider_key)

    cond do
      has_password ->
        {:ok, :durable}

      has_bootstrap and bootstrap_admin_enabled?() ->
        {:ok, :bootstrap_admin}

      true ->
        {:error, :invalid_credentials}
    end
  end

  defp active_credential?(user_id, provider_key)
       when is_binary(user_id) and is_binary(provider_key) do
    Repo.get_by(UserLocalCredentialRow,
      user_id: user_id,
      provider_key: provider_key,
      lifecycle_state: Atom.to_string(:active)
    ) != nil
  end

  defp add_platform_admin_capability(capabilities) when is_list(capabilities) do
    capabilities
    |> List.wrap()
    |> Kernel.++([:platform_admin])
    |> Enum.uniq()
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

  defp issue_user_session(%User{} = user, session_context, current_organization_id) do
    session_token = Token.generate()
    expires_at = DateTime.utc_now() |> DateTime.add(session_ttl_seconds(session_context), :second)

    attrs = %{
      session_token_id: Ids.new("sess"),
      user_id: user.user_id,
      context: session_context,
      token_digest: Token.digest(session_token),
      token_hint: Token.hint(session_token),
      expires_at: expires_at,
      metadata:
        if(session_context == @bootstrap_session_context, do: setup_access_metadata(), else: %{})
    }

    case Repo.insert(UserSessionTokenRow.changeset(attrs)) do
      {:ok, %UserSessionTokenRow{}} ->
        {:ok,
         %{
           user: user,
           session_token: session_token,
           expires_at: expires_at,
           current_organization_id: current_organization_id
         }}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp normalize_session_context(@bootstrap_session_context), do: {:ok, :bootstrap_admin}
  defp normalize_session_context(@browser_session_context), do: {:ok, :browser}
  defp normalize_session_context(_other), do: {:error, :unauthenticated}

  defp bootstrap_admin_config do
    Application.get_env(:cadence, :bootstrap_admin, [])
  end

  defp setup_access_metadata do
    %{"bootstrap_admin" => true, "setup_access" => true}
  end

  defp session_ttl_seconds(@bootstrap_session_context) do
    bootstrap_admin_config()
    |> Keyword.get(:session_ttl_seconds, @default_bootstrap_admin_session_ttl_seconds)
  end

  defp session_ttl_seconds(@browser_session_context), do: @default_browser_session_ttl_seconds

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
