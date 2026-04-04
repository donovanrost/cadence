defmodule Cadence.Accounts do
  @moduledoc """
  Platform user accounts, local credentials, and session tokens.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Accounts.{Password, User}
  alias Cadence.Ids

  alias Cadence.Persistence.Schemas.{
    UserLocalCredentialRow,
    UserRow,
    UserSessionTokenRow
  }

  alias Cadence.Repo

  @bootstrap_provider_key "bootstrap_env"
  @bootstrap_session_context "bootstrap_admin"
  @default_bootstrap_admin_display_name "Bootstrap Admin"
  @default_bootstrap_admin_session_ttl_seconds 86_400

  @type issued_bootstrap_admin_session :: %{
          user: User.t(),
          session_token: binary(),
          expires_at: DateTime.t()
        }

  @spec bootstrap_admin_enabled?() :: boolean()
  def bootstrap_admin_enabled? do
    bootstrap_admin_config()
    |> Keyword.get(:enabled, false)
  end

  @spec ensure_bootstrap_admin() :: {:ok, User.t()} | {:error, term()}
  def ensure_bootstrap_admin do
    if bootstrap_admin_enabled?() do
      config = bootstrap_admin_config()
      email = Keyword.fetch!(config, :email)
      display_name = Keyword.get(config, :display_name, @default_bootstrap_admin_display_name)
      password = Keyword.fetch!(config, :password)

      user =
        User.new(%{
          user_id: Keyword.get(config, :user_id, "user_bootstrap_admin"),
          email: email,
          display_name: display_name,
          capabilities: [:platform_admin],
          lifecycle_state: :active,
          metadata: %{"bootstrap_admin" => true}
        })

      Repo.transaction(fn ->
        with {:ok, persisted_user} <- upsert_user(user),
             :ok <- upsert_bootstrap_credential(persisted_user, password) do
          persisted_user
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, %User{} = persisted_user} -> {:ok, persisted_user}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :bootstrap_admin_disabled}
    end
  end

  @spec login_bootstrap_admin(binary(), binary()) ::
          {:ok, issued_bootstrap_admin_session()} | {:error, term()}
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
      issue_bootstrap_admin_session(user)
    else
      nil -> {:error, :invalid_credentials}
      false -> {:error, :invalid_credentials}
      {:error, _reason} = error -> error
    end
  end

  @spec authenticate_bootstrap_admin_session(binary()) :: {:ok, User.t()} | {:error, term()}
  def authenticate_bootstrap_admin_session(session_token) when is_binary(session_token) do
    with :ok <- ensure_bootstrap_admin_enabled(),
         %UserSessionTokenRow{} = token_row <- active_session_token_row(session_token),
         %UserRow{} = user_row <-
           Repo.get_by(UserRow,
             user_id: token_row.user_id,
             lifecycle_state: Atom.to_string(:active)
           ),
         {:ok, %User{} = user} <- ensure_platform_admin(UserRow.to_domain(user_row)) do
      {:ok, user}
    else
      nil -> {:error, :unauthenticated}
      {:error, _reason} = error -> error
    end
  end

  @spec fetch_user(binary()) :: {:ok, User.t()} | {:error, term()}
  def fetch_user(user_id) when is_binary(user_id) do
    case Repo.get(UserRow, user_id) do
      %UserRow{} = row -> {:ok, UserRow.to_domain(row)}
      nil -> {:error, :user_not_found}
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

  defp active_session_token_row(session_token) do
    token_digest = digest_token(session_token)

    UserSessionTokenRow
    |> where(
      [row],
      row.context == ^@bootstrap_session_context and row.token_digest == ^token_digest and
        row.expires_at > ^DateTime.utc_now()
    )
    |> Repo.one()
  end

  defp issue_bootstrap_admin_session(%User{} = user) do
    session_token = generate_token()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(session_ttl_seconds(), :second)

    attrs = %{
      session_token_id: Ids.new("sess"),
      user_id: user.user_id,
      context: @bootstrap_session_context,
      token_digest: digest_token(session_token),
      token_hint: token_hint(session_token),
      expires_at: expires_at,
      metadata: %{"bootstrap_admin" => true}
    }

    case Repo.insert(UserSessionTokenRow.changeset(attrs)) do
      {:ok, %UserSessionTokenRow{}} ->
        {:ok, %{user: user, session_token: session_token, expires_at: expires_at}}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  defp upsert_user(%User{} = user) do
    case Repo.get_by(UserRow, email: user.email) do
      nil ->
        case Repo.insert(UserRow.changeset(user)) do
          {:ok, %UserRow{} = row} -> {:ok, UserRow.to_domain(row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end

      %UserRow{} = row ->
        attrs = %{
          email: user.email,
          display_name: user.display_name,
          capabilities: Enum.map(user.capabilities, &Atom.to_string/1),
          lifecycle_state: Atom.to_string(user.lifecycle_state),
          metadata: user.metadata
        }

        case Repo.update(UserRow.update_changeset(row, attrs)) do
          {:ok, %UserRow{} = updated_row} -> {:ok, UserRow.to_domain(updated_row)}
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  defp upsert_bootstrap_credential(%User{} = user, password) when is_binary(password) do
    password_document = Password.hash_password(password)

    attrs = %{
      local_credential_id: Ids.new("cred"),
      user_id: user.user_id,
      provider_key: @bootstrap_provider_key,
      password_hash: password_document.password_hash,
      password_salt: password_document.password_salt,
      password_iterations: password_document.password_iterations,
      lifecycle_state: Atom.to_string(:active),
      metadata: %{"bootstrap_admin" => true}
    }

    case Repo.get_by(UserLocalCredentialRow,
           user_id: user.user_id,
           provider_key: @bootstrap_provider_key
         ) do
      nil ->
        case Repo.insert(UserLocalCredentialRow.changeset(attrs)) do
          {:ok, %UserLocalCredentialRow{}} -> :ok
          {:error, %Changeset{} = changeset} -> {:error, changeset}
        end

      %UserLocalCredentialRow{} = row ->
        case Repo.update(
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

  defp bootstrap_admin_config do
    Application.get_env(:cadence, :bootstrap_admin, [])
  end

  defp session_ttl_seconds do
    bootstrap_admin_config()
    |> Keyword.get(:session_ttl_seconds, @default_bootstrap_admin_session_ttl_seconds)
  end

  defp generate_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp digest_token(session_token) when is_binary(session_token) do
    :sha256
    |> :crypto.hash(session_token)
    |> Base.encode16(case: :lower)
  end

  defp token_hint(session_token) do
    session_token
    |> String.slice(-6, 6)
  end
end
