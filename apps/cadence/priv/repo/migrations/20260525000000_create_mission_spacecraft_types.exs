defmodule Cadence.Repo.Migrations.CreateMissionSpacecraftTypes do
  use Ecto.Migration

  def up do
    create table(:mission_spacecraft_types, primary_key: false) do
      add(:spacecraft_type_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:display_name, :string, null: false)
      add(:downlink_protocol, :string, null: false)
      add(:uplink_protocol, :string, null: false)
      add(:packet_protocol, :string, null: false)
      add(:frame_parameters, :map, null: false, default: %{})
      add(:applications, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:mission_spacecraft_types, [:mission_id, :spacecraft_type_id, :version],
        name: :mission_spacecraft_types_scope_idx
      )
    )

    create(
      index(:mission_spacecraft_types, [:organization_id, :mission_id],
        name: :mission_spacecraft_types_org_mission_idx
      )
    )

    execute("""
    ALTER TABLE mission_spacecraft_types
    ADD CONSTRAINT mission_spacecraft_types_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON mission_spacecraft_types
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON mission_spacecraft_types
    """)

    execute("""
    ALTER TABLE mission_spacecraft_types
    DROP CONSTRAINT IF EXISTS mission_spacecraft_types_org_mission_fk
    """)

    drop_if_exists(
      index(:mission_spacecraft_types, [:organization_id, :mission_id],
        name: :mission_spacecraft_types_org_mission_idx
      )
    )

    drop_if_exists(
      index(:mission_spacecraft_types, [:mission_id, :spacecraft_type_id, :version],
        name: :mission_spacecraft_types_scope_idx
      )
    )

    drop(table(:mission_spacecraft_types))
  end
end
