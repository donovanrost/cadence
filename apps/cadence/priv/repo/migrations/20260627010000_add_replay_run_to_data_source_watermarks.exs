defmodule Cadence.Repo.Migrations.AddReplayRunToDataSourceWatermarks do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE data_source_watermark_events ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)"
    )

    execute(
      "ALTER TABLE data_source_watermark_statuses ADD COLUMN IF NOT EXISTS replay_run_id varchar(255)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS data_source_watermark_events_replay_run_idx ON data_source_watermark_events (mission_id, replay_run_id)"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS data_source_watermark_statuses_replay_run_idx ON data_source_watermark_statuses (mission_id, replay_run_id)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS data_source_watermark_statuses_replay_run_idx")
    execute("DROP INDEX IF EXISTS data_source_watermark_events_replay_run_idx")
  end
end
