defmodule Cadence.Repo.Migrations.AddReplayRunToTelemetryBackfillLifecycleEvents do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE telemetry_backfill_lifecycle_events ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)")

    execute(
      "CREATE INDEX IF NOT EXISTS telemetry_backfill_lifecycle_events_replay_idx ON telemetry_backfill_lifecycle_events (organization_id, mission_id, replay_run_id)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS telemetry_backfill_lifecycle_events_replay_idx")
    execute("ALTER TABLE telemetry_backfill_lifecycle_events DROP COLUMN IF EXISTS replay_run_id")
  end
end
