defmodule Cadence.Repo.Migrations.CreatePlatformUsersAndSessions do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :user_id, :string, primary_key: true
      add :email, :string, null: false
      add :display_name, :string, null: false
      add :capabilities, {:array, :string}, null: false, default: []
      add :lifecycle_state, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:user_local_credentials, primary_key: false) do
      add :local_credential_id, :string, primary_key: true

      add :user_id, references(:users, column: :user_id, type: :string, on_delete: :delete_all),
        null: false

      add :provider_key, :string, null: false
      add :password_hash, :string, null: false
      add :password_salt, :string, null: false
      add :password_iterations, :integer, null: false
      add :lifecycle_state, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_local_credentials, [:user_id, :provider_key])

    create table(:user_session_tokens, primary_key: false) do
      add :session_token_id, :string, primary_key: true

      add :user_id, references(:users, column: :user_id, type: :string, on_delete: :delete_all),
        null: false

      add :context, :string, null: false
      add :token_digest, :string, null: false
      add :token_hint, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_session_tokens, [:token_digest])
    create index(:user_session_tokens, [:user_id, :context])
    create index(:user_session_tokens, [:expires_at])
  end
end
