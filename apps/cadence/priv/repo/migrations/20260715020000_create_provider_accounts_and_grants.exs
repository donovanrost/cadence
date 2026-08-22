defmodule Cadence.Repo.Migrations.CreateProviderAccountsAndGrants do
  use Ecto.Migration

  def up do
    create table(:provider_accounts, primary_key: false) do
      add(:provider_account_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:display_name, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:active_version, :integer, null: false)
      add(:credential_status, :string, null: false)
      add(:event_ingestion_status, :string, null: false)
      add(:last_validated_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:provider_accounts, [:organization_id, :lifecycle_state],
        name: :provider_accounts_org_state_idx
      )
    )

    create(
      unique_index(:provider_accounts, [:organization_id, :provider_account_id],
        name: :provider_accounts_org_id_idx
      )
    )

    execute("""
    ALTER TABLE provider_accounts
    ADD CONSTRAINT provider_accounts_org_fk
    FOREIGN KEY (organization_id) REFERENCES organizations (organization_id)
    """)

    create table(:provider_account_versions, primary_key: false) do
      add(:provider_account_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:provider_type, :string, null: false)
      add(:client_key, :string, null: false)
      add(:base_url, :string, null: false)
      add(:region_ref, :string)
      add(:environment_ref, :string, null: false)
      add(:credential_ref, :string, null: false)
      add(:event_ingestion_mode, :string, null: false)
      add(:event_configuration, :map, null: false, default: %{})
      add(:request_policy, :map, null: false, default: %{})
      add(:guardrails, :map, null: false, default: %{})
      add(:provider_configuration, :map, null: false, default: %{})
      add(:created_by, :string)
      add(:created_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:provider_account_versions, [:provider_account_id, :version],
        name: :provider_account_versions_scope_idx
      )
    )

    create(
      unique_index(:provider_account_versions, [:organization_id, :provider_account_id, :version],
        name: :provider_account_versions_org_scope_idx
      )
    )

    execute("""
    ALTER TABLE provider_account_versions
    ADD CONSTRAINT provider_account_versions_account_fk
    FOREIGN KEY (organization_id, provider_account_id)
    REFERENCES provider_accounts (organization_id, provider_account_id)
    """)

    create table(:provider_account_grants, primary_key: false) do
      add(:provider_account_grant_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:provider_account_id, :string, null: false)
      add(:provider_account_version, :integer, null: false)
      add(:version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:restrictions, :map, null: false, default: %{})
      add(:granted_by, :string)
      add(:granted_at, :utc_datetime_usec, null: false)
      add(:grant_reason, :string)
      add(:revoked_by, :string)
      add(:revoked_at, :utc_datetime_usec)
      add(:revoke_reason, :string)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:provider_account_grants, [:provider_account_grant_id, :version],
        name: :provider_account_grants_scope_idx
      )
    )

    create(
      unique_index(
        :provider_account_grants,
        [:organization_id, :mission_id, :provider_account_grant_id, :version],
        name: :provider_account_grants_org_scope_idx
      )
    )

    create(
      index(:provider_account_grants, [:organization_id, :mission_id, :lifecycle_state],
        name: :provider_account_grants_mission_state_idx
      )
    )

    execute("""
    ALTER TABLE provider_account_grants
    ADD CONSTRAINT provider_account_grants_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE provider_account_grants
    ADD CONSTRAINT provider_account_grants_account_version_fk
    FOREIGN KEY (organization_id, provider_account_id, provider_account_version)
    REFERENCES provider_account_versions (organization_id, provider_account_id, version)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON provider_account_grants
    FOR EACH ROW EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON provider_account_grants")
    drop(table(:provider_account_grants))
    drop(table(:provider_account_versions))
    drop(table(:provider_accounts))
  end
end
