defmodule Cadence.Repo.Migrations.AddReplayRunToTelemetryObservationIdentityRecords do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE telemetry_observation_identity_states ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)")
    execute("ALTER TABLE telemetry_observation_identity_decision_events ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)")

    execute(
      "CREATE INDEX IF NOT EXISTS telemetry_observation_identity_states_replay_idx ON telemetry_observation_identity_states (organization_id, mission_id, replay_run_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS telemetry_identity_decision_events_replay_idx ON telemetry_observation_identity_decision_events (organization_id, mission_id, replay_run_id)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS telemetry_identity_decision_events_replay_idx")
    execute("DROP INDEX IF EXISTS telemetry_observation_identity_states_replay_idx")
    execute("ALTER TABLE telemetry_observation_identity_decision_events DROP COLUMN IF EXISTS replay_run_id")
    execute("ALTER TABLE telemetry_observation_identity_states DROP COLUMN IF EXISTS replay_run_id")
  end
end
