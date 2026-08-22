defmodule Cadence.Repo.Migrations.FinishRetiringCatalogSnapshots do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'application_packet_bindings'
          AND column_name = 'telemetry_snapshot_id'
      ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'application_packet_bindings'
          AND column_name = 'mission_model_revision_id'
      ) THEN
        ALTER TABLE application_packet_bindings
          RENAME COLUMN telemetry_snapshot_id TO mission_model_revision_id;
      END IF;
    END
    $$;
    """)

    execute("ALTER TABLE catalog_revisions DROP COLUMN IF EXISTS telemetry_snapshot_id")
    execute("ALTER TABLE catalog_revisions DROP COLUMN IF EXISTS command_snapshot_id")
    execute("ALTER TABLE catalog_import_runs DROP COLUMN IF EXISTS snapshot_id")
    execute("DROP TABLE IF EXISTS catalog_command_snapshots")
    execute("DROP TABLE IF EXISTS catalog_telemetry_snapshots")
  end

  def down do
    raise "removing the retired catalog snapshot model is irreversible"
  end
end
