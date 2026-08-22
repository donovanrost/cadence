defmodule Cadence.Repo.Migrations.CreateMissionProviders do
  use Ecto.Migration

  def up do
    create table(:mission_providers, primary_key: false) do
      add(:provider_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:display_name, :string, null: false)
      add(:provider_type, :string, null: false)
      add(:client_key, :string, null: false)
      add(:base_url, :string, null: false)
      add(:credential_ref, :string, null: false)
      add(:environment_ref, :string, null: false)
      add(:capabilities_document, :map, null: false, default: %{})
      add(:inventory_sync_document, :map, null: false, default: %{})
      add(:last_validated_at, :utc_datetime_usec)
      add(:last_synced_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:mission_providers, [:mission_id, :provider_id, :version],
        name: :mission_providers_scope_idx
      )
    )

    create(
      index(:mission_providers, [:organization_id, :mission_id],
        name: :mission_providers_org_mission_idx
      )
    )

    execute("""
    ALTER TABLE mission_providers
    ADD CONSTRAINT mission_providers_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON mission_providers
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON mission_providers")

    execute("""
    ALTER TABLE mission_providers
    DROP CONSTRAINT IF EXISTS mission_providers_org_mission_fk
    """)

    drop_if_exists(
      index(:mission_providers, [:organization_id, :mission_id],
        name: :mission_providers_org_mission_idx
      )
    )

    drop_if_exists(
      index(:mission_providers, [:mission_id, :provider_id, :version],
        name: :mission_providers_scope_idx
      )
    )

    drop(table(:mission_providers))
  end
end
