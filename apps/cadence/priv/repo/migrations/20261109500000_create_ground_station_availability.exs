defmodule Cadence.Repo.Migrations.CreateGroundStationAvailability do
  use Ecto.Migration

  # S7 station availability (DECISIONS #39): operator-entered and provider-reported windows.
  def up do
    create table(:ground_station_availability_windows, primary_key: false) do
      add(:window_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:ground_station_id, :string, null: false)
      add(:kind, :string, null: false)
      add(:starts_at, :utc_datetime_usec, null: false)
      add(:ends_at, :utc_datetime_usec)
      add(:eta, :utc_datetime_usec)
      add(:source, :string, null: false)
      add(:reported_by, :map, null: false, default: %{})
      add(:provider_ref, :string)
      add(:reason, :text)
      add(:detail, :map, null: false, default: %{})
      add(:cleared_at, :utc_datetime_usec)
      add(:cleared_by, :map)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:ground_station_availability_windows, [:mission_id, :ground_station_id, :starts_at]))

    create(
      unique_index(:ground_station_availability_windows, [:mission_id, :provider_ref],
        where: "provider_ref IS NOT NULL",
        name: :ground_station_availability_provider_ref_idx
      )
    )

    execute("""
    ALTER TABLE ground_station_availability_windows
    ADD CONSTRAINT ground_station_availability_windows_org_mission_fk
    FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON ground_station_availability_windows
    FOR EACH ROW EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    drop(table(:ground_station_availability_windows))
  end
end
