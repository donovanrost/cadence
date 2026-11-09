defmodule Cadence.Repo.Migrations.CreateActivationFleets do
  use Ecto.Migration

  # Content-addressed fleet snapshots for activation metadata v2
  # (docs/apogee/domain/fleet-snapshot.md). A fleet is referenced from metadata by its hash;
  # identical entries and identical fleets are stored once per mission.
  def up do
    create table(:activation_fleets, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:fleet_sha256, :string, primary_key: true)
      add(:organization_id, :string)
      add(:spacecraft_count, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create table(:activation_fleet_entries, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:entry_sha256, :string, primary_key: true)
      add(:organization_id, :string)
      add(:entry, :map, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create table(:activation_fleet_members, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:fleet_sha256, :string, primary_key: true)
      add(:spacecraft_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:entry_sha256, :string, null: false)
      add(:source_endpoint_ids, {:array, :string}, null: false)
      add(:commanding_enabled, :boolean, null: false)
      add(:catalog_revision_id, :string, null: false)
      add(:mission_model_sha256, :string, null: false)
    end

    execute("""
    CREATE INDEX activation_fleet_members_sources_idx
    ON activation_fleet_members USING GIN (source_endpoint_ids)
    """)

    create(
      index(:activation_fleet_members, [:mission_id, :fleet_sha256, :commanding_enabled],
        name: :activation_fleet_members_commanding_idx
      )
    )

    for table <- [:activation_fleets, :activation_fleet_entries, :activation_fleet_members] do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_org_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      """)

      execute("""
      CREATE TRIGGER sync_organization_id_from_mission
      BEFORE INSERT OR UPDATE OF mission_id, organization_id ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
      """)
    end
  end

  def down do
    drop(table(:activation_fleet_members))
    drop(table(:activation_fleet_entries))
    drop(table(:activation_fleets))
  end
end
