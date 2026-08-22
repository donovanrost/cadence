defmodule Cadence.Repo.Migrations.CreateProviderCredentials do
  use Ecto.Migration

  def change do
    create table(:provider_credentials, primary_key: false) do
      add(:provider_credential_ref, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:provider_account_id, :string, null: false)
      add(:status, :string, null: false)
      add(:registry_version, :integer, null: false)
      add(:backend_type, :string, null: false)
      add(:backend_key, :string, null: false)
      add(:backend_reference, :string)
      add(:registered_at, :utc_datetime_usec, null: false)
      add(:last_resolved_at, :utc_datetime_usec)
      add(:last_rotated_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:provider_credentials, [:organization_id, :provider_account_id, :status],
        name: :provider_credentials_account_status_idx
      )
    )

    create(
      constraint(:provider_credentials, :provider_credentials_status_check,
        check: "status IN ('active', 'revoked')"
      )
    )

    create(
      constraint(:provider_credentials, :provider_credentials_backend_type_check,
        check: "backend_type IN ('env', 'external')"
      )
    )

    create(
      constraint(:provider_credentials, :provider_credentials_registry_version_check,
        check: "registry_version > 0"
      )
    )
  end
end
