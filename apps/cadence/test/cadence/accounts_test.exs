defmodule Cadence.AccountsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts
  alias Cadence.Accounts.{Password, User}
  alias Cadence.Ids
  alias Cadence.Persistence.Schemas.{UserLocalCredentialRow, UserRow}
  alias Cadence.Repo

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  describe "sign_in/2" do
    setup do
      previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])

      on_exit(fn ->
        Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
      end)

      :ok
    end

    test "durable user with only a password credential can sign in" do
      password = "durable-password-123"
      persist_durable_user!(email: "ops@example.com", password: password)

      assert {:ok, session} = Accounts.sign_in("ops@example.com", password)
      assert session.temporary_setup_access? == false
      assert is_binary(session.session_token)
    end

    test "durable user with wrong password fails with :invalid_credentials" do
      persist_durable_user!(email: "ops@example.com", password: "correct")

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "wrong")
    end

    test "unconfirmed durable user fails with :invalid_credentials" do
      persist_durable_user!(email: "ops@example.com", password: "pw-123", confirmed_at: nil)

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "pw-123")
    end

    test "inactive durable user fails with :invalid_credentials" do
      persist_durable_user!(
        email: "ops@example.com",
        password: "pw-123",
        lifecycle_state: :disabled
      )

      assert {:error, :invalid_credentials} = Accounts.sign_in("ops@example.com", "pw-123")
    end

    test "bootstrap admin with enabled config and pending setup can sign in" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

      assert {:ok, session} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)

      assert session.temporary_setup_access? == true
      assert is_binary(session.session_token)
    end

    test "bootstrap admin with wrong password fails with :invalid_credentials" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, "wrong")
    end

    test "bootstrap admin with bootstrap_admin_enabled? false fails with :invalid_credentials" do
      enable_bootstrap_admin!()
      assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

      Application.put_env(:cadence, :bootstrap_admin, enabled: false)

      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)
    end

    test "user with both credentials dispatches to durable path when durable password is correct" do
      enable_bootstrap_admin!()
      assert {:ok, _bootstrap_user} = Cadence.ensure_bootstrap_admin()

      # Attach a password credential to the bootstrap admin user so it has both.
      durable_password = "durable-password-123"
      attach_password_credential!(@bootstrap_admin_email, durable_password)

      assert {:ok, session} = Accounts.sign_in(@bootstrap_admin_email, durable_password)
      assert session.temporary_setup_access? == false
    end

    test "user with both credentials does not fall back to bootstrap when durable password is wrong" do
      enable_bootstrap_admin!()
      assert {:ok, _bootstrap_user} = Cadence.ensure_bootstrap_admin()

      durable_password = "durable-password-123"
      attach_password_credential!(@bootstrap_admin_email, durable_password)

      # Submitting the bootstrap password, which would succeed against the bootstrap
      # credential, must NOT succeed via sign_in/2 because durable is present and wins.
      assert {:error, :invalid_credentials} =
               Accounts.sign_in(@bootstrap_admin_email, @bootstrap_admin_password)
    end

    test "email not found fails with :invalid_credentials" do
      assert {:error, :invalid_credentials} =
               Accounts.sign_in("nobody@example.com", "anything")
    end
  end

  ## Fixtures

  defp enable_bootstrap_admin! do
    Application.put_env(:cadence, :bootstrap_admin,
      enabled: true,
      user_id: "user_bootstrap_admin",
      email: @bootstrap_admin_email,
      display_name: "Bootstrap Admin",
      password: @bootstrap_admin_password,
      session_ttl_seconds: 3600
    )
  end

  defp persist_durable_user!(opts) when is_list(opts) do
    password = Keyword.fetch!(opts, :password)
    email = Keyword.fetch!(opts, :email)
    confirmed_at = Keyword.get(opts, :confirmed_at, DateTime.utc_now())
    lifecycle_state = Keyword.get(opts, :lifecycle_state, :active)

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: Keyword.get(opts, :display_name, "Durable User"),
        capabilities: Keyword.get(opts, :capabilities, []),
        confirmed_at: confirmed_at,
        lifecycle_state: lifecycle_state,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  defp attach_password_credential!(email, password) do
    normalized_email = User.normalize_email(email)
    %UserRow{} = user_row = Repo.get_by!(UserRow, email: normalized_email)

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user_row.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    # Ensure the bootstrap admin user is confirmed for the durable path.
    Repo.update!(UserRow.update_changeset(user_row, %{confirmed_at: DateTime.utc_now()}))
  end
end
