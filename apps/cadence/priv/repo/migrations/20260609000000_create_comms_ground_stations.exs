defmodule Cadence.Repo.Migrations.CreateCommsGroundStations do
  use Ecto.Migration

  def up do
    create table(:comms_ground_stations, primary_key: false) do
      add(:ground_station_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:display_name, :string, null: false)
      add(:provider, :string)
      add(:region, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:comms_ground_stations, [:mission_id, :ground_station_id],
        name: :comms_ground_stations_scope_idx
      )
    )

    create(
      index(:comms_ground_stations, [:organization_id, :mission_id],
        name: :comms_ground_stations_org_mission_idx
      )
    )

    execute("""
    ALTER TABLE comms_ground_stations
    ADD CONSTRAINT comms_ground_stations_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON comms_ground_stations
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON comms_ground_stations
    """)

    execute("""
    ALTER TABLE comms_ground_stations
    DROP CONSTRAINT IF EXISTS comms_ground_stations_org_mission_fk
    """)

    drop_if_exists(
      index(:comms_ground_stations, [:organization_id, :mission_id],
        name: :comms_ground_stations_org_mission_idx
      )
    )

    drop_if_exists(
      index(:comms_ground_stations, [:mission_id, :ground_station_id],
        name: :comms_ground_stations_scope_idx
      )
    )

    drop(table(:comms_ground_stations))
  end
end
