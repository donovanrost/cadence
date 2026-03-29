defmodule Cadence.Repo.Migrations.CreateMissionSpacecraft do
  use Ecto.Migration

  def up do
    create table(:mission_spacecraft, primary_key: false) do
      add(:spacecraft_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:display_name, :string, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:mission_spacecraft, [:mission_id, :spacecraft_id],
        name: :mission_spacecraft_scope_idx
      )
    )

    create(
      unique_index(:mission_spacecraft, [:organization_id, :mission_id, :spacecraft_id],
        name: :mission_spacecraft_org_scope_idx
      )
    )

    create(
      index(:mission_spacecraft, [:organization_id, :mission_id],
        name: :mission_spacecraft_org_mission_idx
      )
    )

    execute("""
    ALTER TABLE mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON mission_spacecraft
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    execute("""
    ALTER TABLE mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_scope_idx_uniq
    UNIQUE USING INDEX mission_spacecraft_scope_idx
    """)

    execute("""
    ALTER TABLE mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_org_scope_idx_uniq
    UNIQUE USING INDEX mission_spacecraft_org_scope_idx
    """)

    execute("""
    ALTER TABLE mission_source_endpoints
    ADD CONSTRAINT mission_source_endpoints_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON mission_spacecraft
    """)

    execute("""
    ALTER TABLE mission_source_endpoints
    DROP CONSTRAINT IF EXISTS mission_source_endpoints_spacecraft_fk
    """)

    execute("""
    ALTER TABLE mission_spacecraft
    DROP CONSTRAINT IF EXISTS mission_spacecraft_org_mission_fk
    """)

    execute("""
    ALTER TABLE mission_spacecraft
    DROP CONSTRAINT IF EXISTS mission_spacecraft_org_scope_idx_uniq
    """)

    execute("""
    ALTER TABLE mission_spacecraft
    DROP CONSTRAINT IF EXISTS mission_spacecraft_scope_idx_uniq
    """)

    drop_if_exists(
      index(:mission_spacecraft, [:organization_id, :mission_id],
        name: :mission_spacecraft_org_mission_idx
      )
    )

    drop_if_exists(
      index(:mission_spacecraft, [:organization_id, :mission_id, :spacecraft_id],
        name: :mission_spacecraft_org_scope_idx
      )
    )

    drop_if_exists(
      index(:mission_spacecraft, [:mission_id, :spacecraft_id],
        name: :mission_spacecraft_scope_idx
      )
    )

    drop(table(:mission_spacecraft))
  end
end
