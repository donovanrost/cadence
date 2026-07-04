defmodule Cadence.Repo.Migrations.AddReplayRunToDashboardSourceHealth do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE dashboard_source_health_events ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)")
    execute("ALTER TABLE dashboard_source_health_statuses ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)")

    execute(
      "CREATE INDEX IF NOT EXISTS dashboard_source_health_events_replay_idx ON dashboard_source_health_events (organization_id, mission_id, replay_run_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS dashboard_source_health_statuses_replay_idx ON dashboard_source_health_statuses (organization_id, mission_id, replay_run_id)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS dashboard_source_health_statuses_replay_idx")
    execute("DROP INDEX IF EXISTS dashboard_source_health_events_replay_idx")
    execute("ALTER TABLE dashboard_source_health_statuses DROP COLUMN IF EXISTS replay_run_id")
    execute("ALTER TABLE dashboard_source_health_events DROP COLUMN IF EXISTS replay_run_id")
  end
end
